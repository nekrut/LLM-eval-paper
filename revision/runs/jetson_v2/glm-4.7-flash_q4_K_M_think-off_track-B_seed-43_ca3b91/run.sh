#!/usr/bin/env bash
set -euo pipefail

# Directories
RAW_DIR="data/raw"
REF_DIR="data/ref"
OUT_DIR="results"

# Create output directory if it doesn't exist
mkdir -p "$OUT_DIR"

# Reference file
REF="$REF_DIR/chrM.fa"

# Index reference if not already indexed
if [ ! -f "$REF.bai" ]; then
    samtools index "$REF"
fi

# Function to process a single sample
process_sample() {
    local sample="$1"
    local r1="$RAW_DIR/${sample}_1.fq.gz"
    local r2="$RAW_DIR/${sample}_2.fq.gz"
    local bam="$OUT_DIR/${sample}.bam"
    local vcf="$OUT_DIR/${sample}.vcf.gz"

    # Check if outputs already exist
    if [ -f "$bam" ] && [ -f "$bam.bai" ] && [ -f "$vcf" ] && [ -f "${vcf}.tbi" ]; then
        return 0
    fi

    # Align with BWA
    bwa mem -t 4 "$REF" "$r1" "$r2" | \
    samtools view -b - > "$bam"

    # Sort and index BAM
    samtools sort -@ 2 -o "${bam}.sorted" "$bam"
    mv "${bam}.sorted" "$bam"
    samtools index "$bam"

    # Call variants with LoFreq
    lofreq call-parallel -f "$REF" -o "$vcf" -m indel -q 20 -C 20 -t 2 "$bam"
    tabix -p vcf "$vcf"
}

# Process all samples
process_sample "M117-bl"
process_sample "M117-ch"
process_sample "M117C1-bl"
process_sample "M117C1-ch"

# Collapse VCFs into a single TSV
# Using bcftools to concatenate and filter
bcftools concat -Oz -o "$OUT_DIR/merged.vcf.gz" \
    "$OUT_DIR/M117-bl.vcf.gz" \
    "$OUT_DIR/M117-ch.vcf.gz" \
    "$OUT_DIR/M117C1-bl.vcf.gz" \
    "$OUT_DIR/M117C1-ch.vcf.gz"

# Extract INFO fields and convert to TSV
bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "$OUT_DIR/merged.vcf.gz" | \
    sed 's/,/\t/g' > "$OUT_DIR/collapsed.tsv"

# Cleanup intermediate merged VCF
rm "$OUT_DIR/merged.vcf.gz" "$OUT_DIR/merged.vcf.gz.tbi"

exit 0