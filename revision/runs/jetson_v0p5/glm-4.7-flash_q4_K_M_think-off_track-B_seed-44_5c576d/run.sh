#!/usr/bin/env bash
set -euo pipefail

THREADS=4
RAW_DIR="data/raw"
REF_DIR="data/ref"
OUT_DIR="results"

mkdir -p "$OUT_DIR"

# Index reference if not present
if [ ! -f "$REF_DIR/chrM.fa.bwt" ]; then
    bwa index "$REF_DIR/chrM.fa"
fi

# Function to process a single sample
process_sample() {
    local sample="$1"
    local r1="$RAW_DIR/${sample}_1.fq.gz"
    local r2="$RAW_DIR/${sample}_2.fq.gz"
    local bam="$OUT_DIR/${sample}.bam"
    local vcf="$OUT_DIR/${sample}.vcf.gz"

    # Skip if BAM and VCF already exist
    if [ -f "$bam" ] && [ -f "$vcf" ]; then
        return 0
    fi

    # Align
    bwa mem -t "$THREADS" "$REF_DIR/chrM.fa" "$r1" "$r2" | \
    samtools view -b -F 4 - > "$bam"

    # Sort and Index
    samtools sort -@ "$THREADS" -o "${bam}.sorted" "$bam"
    mv "${bam}.sorted" "$bam"
    samtools index "$bam"

    # Call Variants
    lofreq call-parallel -f "$REF_DIR/chrM.fa" -o "$vcf" -m lofreq -t "$THREADS" "$bam"

    # Index VCF
    tabix -p vcf "$vcf"
}

# Process all samples
process_sample "M117-bl"
process_sample "M117-ch"
process_sample "M117C1-bl"
process_sample "M117C1-ch"

# Collapse VCFs
bcftools concat -Oz -o "$OUT_DIR/merged.vcf.gz" \
    "$OUT_DIR/M117-bl.vcf.gz" \
    "$OUT_DIR/M117-ch.vcf.gz" \
    "$OUT_DIR/M117C1-bl.vcf.gz" \
    "$OUT_DIR/M117C1-ch.vcf.gz"

tabix -p vcf "$OUT_DIR/merged.vcf.gz"

# Filter and Format
bcftools view -f PASS -Oz -o "$OUT_DIR/filtered.vcf.gz" "$OUT_DIR/merged.vcf.gz"
tabix -p vcf "$OUT_DIR/filtered.vcf.gz"

# Extract INFO/AF and format for collapse
bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "$OUT_DIR/filtered.vcf.gz" | \
    awk 'NR>1 {print $1"\t"$2"\t"$3"\t"$4"\t"$5}' > "$OUT_DIR/collapsed.tsv"

exit 0