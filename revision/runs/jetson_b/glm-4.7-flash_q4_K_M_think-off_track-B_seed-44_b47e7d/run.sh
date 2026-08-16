#!/usr/bin/env bash
set -euo pipefail

# Directory setup
RAW_DIR="data/raw"
REF_DIR="data/ref"
OUT_DIR="results"
mkdir -p "$OUT_DIR"

# Define samples
declare -a SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

# Create a temporary directory for intermediate files
TMP_DIR=$(mktemp -d)
trap "rm -rf $TMP_DIR" EXIT

# Index reference if not already done
if [ ! -f "$REF_DIR/chrM.fa.bwt" ]; then
    bwa index "$REF_DIR/chrM.fa"
fi

# Function to process a single sample
process_sample() {
    local SAMPLE=$1
    local R1="${RAW_DIR}/${SAMPLE}_1.fq.gz"
    local R2="${RAW_DIR}/${SAMPLE}_2.fq.gz"
    local BAM="${OUT_DIR}/${SAMPLE}.bam"
    local VCF="${OUT_DIR}/${SAMPLE}.vcf.gz"

    # Check if outputs already exist
    if [ -f "$BAM" ] && [ -f "$BAM.bai" ] && [ -f "$VCF" ] && [ -f "$VCF.tbi" ]; then
        return 0
    fi

    # 1. Align reads
    bwa mem -t 4 "$REF_DIR/chrM.fa" "$R1" "$R2" | \
        samtools view -b - > "$TMP_DIR/${SAMPLE}.sam"

    # 2. Sort and index BAM
    samtools sort -@ 2 -o "$BAM" "$TMP_DIR/${SAMPLE}.sam"
    samtools index "$BAM"

    # 3. Call variants
    lofreq call-parallel -f "$REF_DIR/chrM.fa" -o "$VCF" -m lofreq -C 20 -t 2 "$BAM"

    # 4. Index VCF
    tabix -p vcf "$VCF"
}

# Process all samples
for SAMPLE in "${SAMPLES[@]}"; do
    process_sample "$SAMPLE"
done

# 5. Collapsing VCFs
# Use bcftools to concatenate and then collapse
bcftools concat -Oz -o "$OUT_DIR/concatenated.vcf.gz" "${OUT_DIR}"/*.vcf.gz
tabix -p vcf "$OUT_DIR/concatenated.vcf.gz"

# Use bcftools query to extract required fields and format the table
bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%AF\n' "$OUT_DIR/concatenated.vcf.gz" > "$OUT_DIR/collapsed.tsv"

# Cleanup intermediate concatenated file
rm "$OUT_DIR/concatenated.vcf.gz"
rm "$OUT_DIR/concatenated.vcf.gz.tbi"

exit 0