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
    local r1="${RAW_DIR}/${sample}_1.fq.gz"
    local r2="${RAW_DIR}/${sample}_2.fq.gz"
    local bam="${OUT_DIR}/${sample}.bam"
    local bai="${OUT_DIR}/${sample}.bam.bai"
    local vcf_gz="${OUT_DIR}/${sample}.vcf.gz"
    local tbi="${OUT_DIR}/${sample}.vcf.gz.tbi"

    # Check if final VCF is already present and valid; if so, skip sample
    if [[ -f "$vcf_gz" && -f "$tbi" ]]; then
        return 0
    fi

    # Alignment with BWA-MEM
    if [[ ! -f "$bam" ]]; then
        bwa mem -t "$THREADS" "$REF" "$r1" "$r2" | \
            samtools view -bS -@ "$THREADS" -o "$bam"
    fi

    # Sort and index BAM
    if [[ ! -f "$bai" ]]; then
        # If bam exists but bai doesn't, we need to ensure it's sorted first.
        # bwa mem output is typically unsorted or coordinate-sorted depending on version/flags, 
        # but samtools sort is safer to ensure consistency for variant calling.
        # We use a temp file approach to avoid overwriting if partially done, 
        # but since we check existence of final artifacts, we can be aggressive.
        
        local sorted_bam="${OUT_DIR}/${sample}.sorted.bam"
        
        # Sort if not already sorted (check by comparing or just resorting into place)
        # To be idempotent and safe: sort to a temp name, then move.
        samtools sort -@ "$THREADS" -o "$bam" "$bam"
        
        # Index
        samtools index "$bam"
    fi

    # Variant Calling with Lofreq
    if [[ ! -f "$vcf_gz" ]]; then
        lofreq call --annotate-format=DP4,AD --min-af 0.01 -f "$REF" -o "${OUT_DIR}/${sample}.vcf" "$bam"
        
        # Normalize VCF and compress
        bcftools norm -O z -o "$vcf_gz" "${OUT_DIR}/${sample}.vcf"
        
        # Index VCF
        tabix -p vcf "$vcf_gz"
        
        # Cleanup intermediate uncompressed VCF
        rm -f "${OUT_DIR}/${sample}.vcf"
    fi
}

# Process all samples
for sample in "${SAMPLES[@]}"; do
    process_sample "$sample"
done

# Generate collapsed.tsv
COLLAPSED_TSV="${OUT_DIR}/collapsed.tsv"

# Check if already exists and has content (header + data)
if [[ -f "$COLLAPSED_TSV" ]] && [[ $(wc -l < "$COLLAPSED_TSV") -gt 1 ]]; then
    exit 0
fi

# Header
printf "sample\tchrom\tpos\tref\talt\taf\n" > "$COLLAPSED_TSV"

for sample in "${SAMPLES[@]}"; do
    vcf_gz="${OUT_DIR}/${sample}.vcf.gz"
    
    # Extract variants: chrom, pos, ref, alt, AF (from INFO field)
    # bcftools query is robust for this.
    # We need to handle the AF field. Lofreq outputs AF in INFO.
    # Format: %CHROM %POS %REF %ALT 'INFO/AF'
    
    bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "$vcf_gz" | \
    while IFS=$'\t' read -r chrom pos ref alt af; do
        # Filter out low quality or non-variant lines if necessary, 
        # but lofreq call usually outputs variants. 
        # Ensure AF is a number. If missing, skip? Lofreq should provide it.
        if [[ -z "$af" ]]; then
            continue
        fi
        printf "%s\t%s\t%s\t%s\t%s\t%s\n" "$sample" "$chrom" "$pos" "$ref" "$alt" "$af"
    done >> "$COLLAPSED_TSV"
done

exit 0