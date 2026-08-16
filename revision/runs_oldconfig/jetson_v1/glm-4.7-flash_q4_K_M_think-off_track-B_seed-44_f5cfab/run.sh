#!/usr/bin/env bash
set -euo pipefail

# Directories
RAW_DIR="data/raw"
REF_DIR="data/ref"
OUT_DIR="results"

# Tool checks
for tool in bwa samtools bcftools tabix lofreq java; do
    if ! command -v "$tool" &> /dev/null; then
        echo "Error: Tool '$tool' not found in PATH." >&2
        exit 1
    fi
done

# Create output directory if it doesn't exist
mkdir -p "$OUT_DIR"

# Index reference
if [ ! -f "$REF_DIR/chrM.fa.bai" ]; then
    bwa index "$REF_DIR/chrM.fa"
    samtools faidx "$REF_DIR/chrM.fa"
fi

# Function to process a single sample
process_sample() {
    local sample="$1"
    local r1="$RAW_DIR/${sample}_1.fq.gz"
    local r2="$RAW_DIR/${sample}_2.fq.gz"
    local bam="$OUT_DIR/${sample}.bam"
    local vcf="$OUT_DIR/${sample}.vcf.gz"

    # Check if outputs already exist
    if [ -f "$bam" ] && [ -f "$bam.bai" ] && [ -f "$vcf" ] && [ -f "$vcf.tbi" ]; then
        return 0
    fi

    # Align
    bwa mem -t 4 "$REF_DIR/chrM.fa" "$r1" "$r2" | \
    samtools view -b -F 4 - | \
    samtools sort -@ 2 -o "$bam" -

    # Index BAM
    samtools index "$bam"

    # Call variants
    lofreq call-parallel -f "$REF_DIR/chrM.fa" -o "$vcf" -m lofreq -q 20 -C 20 -t 2 "$bam"

    # Index VCF
    tabix -p vcf "$vcf"
}

# Process all samples
process_sample "M117-bl"
process_sample "M117-ch"
process_sample "M117C1-bl"
process_sample "M117C1-ch"

# Collapse VCFs
# Using bcftools merge to combine VCFs, then filtering for PASS and INFO fields
# Then extracting relevant columns and sorting
bcftools merge -Oz -o "$OUT_DIR/merged.vcf.gz" "$OUT_DIR"/*.vcf.gz
tabix -p vcf "$OUT_DIR/merged.vcf.gz"

# Filter and format
# bcftools query to extract sample, chrom, pos, ref, alt, and allele frequency
# AF is calculated per sample in the VCF
bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%AF\n' "$OUT_DIR/merged.vcf.gz" | \
grep -v '^\.' | \
sort -k1,1 -k2,2n > "$OUT_DIR/collapsed.tsv"

echo "Done."