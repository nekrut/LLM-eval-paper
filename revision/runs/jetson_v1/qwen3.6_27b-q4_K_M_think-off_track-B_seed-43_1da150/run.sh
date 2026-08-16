#!/usr/bin/env bash
set -euo pipefail

# Configuration
REF="data/ref/chrM.fa"
RAW_DIR="data/raw"
OUT_DIR="results"
THREADS=4

SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

# Create output directory if it doesn't exist
mkdir -p "$OUT_DIR"

# Index reference if not already indexed
if [[ ! -f "${REF}.fai" ]]; then
    samtools faidx "$REF"
fi

# Function to process a single sample
process_sample() {
    local sample="$1"
    local fq1="${RAW_DIR}/${sample}_1.fq.gz"
    local fq2="${RAW_DIR}/${sample}_2.fq.gz"
    local bam="${OUT_DIR}/${sample}.bam"
    local bai="${OUT_DIR}/${sample}.bam.bai"
    local vcf_gz="${OUT_DIR}/${sample}.vcf.gz"
    local tbi="${OUT_DIR}/${sample}.vcf.gz.tbi"

    # Check if all outputs exist and are non-empty (idempotency)
    if [[ -s "$bam" && -s "$bai" && -s "$vcf_gz" && -s "$tbi" ]]; then
        return 0
    fi

    # Step 1: Alignment with BWA
    local sam_tmp="${OUT_DIR}/${sample}.sam"
    if [[ ! -s "$bam" ]]; then
        bwa mem -t "$THREADS" "$REF" "$fq1" "$fq2" > "$sam_tmp"
        samtools view -b -o "$bam" "$sam_tmp"
        rm -f "$sam_tmp"
    fi

    # Step 2: Sort and Index BAM
    if [[ ! -s "$bai" ]]; then
        # If bam exists but bai doesn't, we need to sort first if not already sorted
        # bwa mem output is typically unsorted. Let's ensure it's sorted by coordinate.
        local sorted_bam="${OUT_DIR}/${sample}.sorted.bam"
        samtools sort -@ "$THREADS" -o "$bam" "$bam"
        mv "$bam" "$sorted_bam" # Move to temp name to avoid confusion during index
        mv "$sorted_bam" "$bam" # Rename back
        
        samtools index "$bam" "$bai"
    fi

    # Step 3: Variant Calling with Lofreq
    if [[ ! -s "$vcf_gz" ]]; then
        lofreq call --call-indels -f "$REF" -o "${OUT_DIR}/${sample}.vcf" "$bam"
        
        # Compress and index VCF
        bgzip -c "${OUT_DIR}/${sample}.vcf" > "$vcf_gz"
        tabix -p vcf "$vcf_gz" "$tbi"
        
        rm -f "${OUT_DIR}/${sample}.vcf"
    fi
}

# Process all samples
for sample in "${SAMPLES[@]}"; do
    process_sample "$sample"
done

# Step 4: Create collapsed TSV
COLLAPSED_TSV="${OUT_DIR}/collapsed.tsv"

# Check if already exists and has content (idempotency)
if [[ -s "$COLLAPSED_TSV" ]]; then
    exit 0
fi

# Header
printf "sample\tchrom\tpos\tref\talt\taf\n" > "$COLLAPSED_TSV"

for sample in "${SAMPLES[@]}"; do
    vcf_gz="${OUT_DIR}/${sample}.vcf.gz"
    
    # Extract variants using bcftools query
    # FORMAT/AF is the allele frequency. If missing, we might need to calculate or default.
    # Lofreq usually provides AF in INFO or FORMAT. Let's check standard fields.
    # Standard VCF: CHROM POS ID REF ALT QUAL FILTER INFO FORMAT SAMPLES
    # Lofreq output typically has AF in INFO field or FORMAT/AF.
    # Let's try to get AF from INFO first, then FORMAT if needed.
    
    bcftools query -f '%CHROM\t%POS\t%REF\t%ALT[\t%INFO/AF]\n' "$vcf_gz" | \
    while IFS=$'\t' read -r chrom pos ref alt af; do
        # Handle multi-allelic sites if necessary, but simple loop assumes one ALT per line for simplicity in query format above.
        # If AF is missing or '.', we might need to handle it.
        if [[ "$af" == "." || -z "$af" ]]; then
            af="NA"
        fi
        printf "%s\t%s\t%s\t%s\t%s\t%s\n" "$sample" "$chrom" "$pos" "$ref" "$alt" "$af"
    done >> "$COLLAPSED_TSV"
done

exit 0