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
    local bai="${bam}.bai"
    local vcf_gz="${OUT_DIR}/${sample}.vcf.gz"
    local tbi="${vcf_gz}.tbi"

    # Check if all outputs for this sample already exist and are valid
    if [[ -f "$bam" && -f "$bai" && -f "$vcf_gz" && -f "$tbi" ]]; then
        return 0
    fi

    # Align reads using BWA-MEM
    bwa mem -t "$THREADS" "$REF" "$r1" "$r2" | \
        samtools view -bS -o "$bam"

    # Sort and index BAM
    samtools sort -@ "$THREADS" -o "$bam" "$bam"
    samtools index "$bam"

    # Call variants using LoFreq
    # --min-af 0.01 to detect low frequency variants typical in mtDNA heteroplasmy
    # --call-indels to include indels
    lofreq call -f "$REF" --min-af 0.01 --call-indels -o "${OUT_DIR}/${sample}.vcf" "$bam"

    # Filter and format VCF
    # Keep only high quality variants, remove duplicates if any (though amplicon usually low dup rate or handled by lofreq)
    bcftools filter -i 'QUAL>20' -Oz -o "$vcf_gz" "${OUT_DIR}/${sample}.vcf"

    # Index VCF
    tabix -p vcf "$vcf_gz"

    # Clean up intermediate uncompressed VCF
    rm -f "${OUT_DIR}/${sample}.vcf"
}

# Process each sample
for sample in "${SAMPLES[@]}"; do
    process_sample "$sample"
done

# Generate collapsed TSV
COLLAPSED_TSV="${OUT_DIR}/collapsed.tsv"

# Check if collapsed TSV already exists and is non-empty
if [[ -s "$COLLAPSED_TSV" ]]; then
    exit 0
fi

# Header
printf "sample\tchrom\tpos\tref\talt\taf\n" > "$COLLAPSED_TSV"

for sample in "${SAMPLES[@]}"; do
    vcf_gz="${OUT_DIR}/${sample}.vcf.gz"
    
    # Extract variant information using bcftools query
    # %CHROM %POS %REF %ALT %INFO/AF
    # Note: LoFreq outputs AF in INFO field. If not present, we might need to calculate from AD/DP or use FORMAT/AF if available.
    # LoFreq typically puts allele frequency in INFO/AF or FORMAT/AF. Let's check standard output.
    # Standard lofreq call output has AF in INFO.
    
    bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "$vcf_gz" | \
    while IFS=$'\t' read -r chrom pos ref alt af; do
        # Handle missing AF values if any (replace with NA or calculate)
        if [[ -z "$af" || "$af" == "." ]]; then
            af="NA"
        fi
        printf "%s\t%s\t%s\t%s\t%s\t%s\n" "$sample" "$chrom" "$pos" "$ref" "$alt" "$af"
    done >> "$COLLAPSED_TSV"
done

exit 0