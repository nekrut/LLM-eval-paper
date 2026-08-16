#!/usr/bin/env bash
set -euo pipefail

# Directories
RAW_DIR="data/raw"
REF_DIR="data/ref"
OUT_DIR="results"

# Ensure output directory exists
mkdir -p "$OUT_DIR"

# Reference genome path
REF_FA="$REF_DIR/chrM.fa"

# Index reference if not already present
if [ ! -f "$REF_FA.bai" ]; then
    samtools index "$REF_FA"
fi

# Function to process a single sample
process_sample() {
    local sample="$1"
    local r1="$RAW_DIR/${sample}_1.fq.gz"
    local r2="$RAW_DIR/${sample}_2.fq.gz"
    local bam="$OUT_DIR/${sample}.bam"
    local vcf="$OUT_DIR/${sample}.vcf.gz"

    # Skip if BAM and VCF already exist
    if [ -f "$bam" ] && [ -f "$bam.bai" ] && [ -f "$vcf" ] && [ -f "$vcf.tbi" ]; then
        return 0
    fi

    # 1. Align with BWA-MEM
    bwa mem -t 4 "$REF_FA" "$r1" "$r2" | \
    samtools view -b - > "$bam"

    # 2. Sort and Index BAM
    samtools sort -@ 2 -o "${bam}.sorted" "$bam"
    mv "${bam}.sorted" "$bam"
    samtools index "$bam"

    # 3. Call variants with LoFreq
    lofreq call-parallel -f "$REF_FA" -o "$vcf" -m indel -q 20 -C 50 -t 2 "$bam"

    # 4. Index VCF
    tabix -p vcf "$vcf"
}

# Process all samples
process_sample "M117-bl"
process_sample "M117-ch"
process_sample "M117C1-bl"
process_sample "M117C1-ch"

# 5. Collapsing VCFs into a single TSV
# Using bcftools to concatenate and filter
bcftools concat -Oz -o "$OUT_DIR/merged.vcf.gz" \
    "$OUT_DIR/M117-bl.vcf.gz" \
    "$OUT_DIR/M117-ch.vcf.gz" \
    "$OUT_DIR/M117C1-bl.vcf.gz" \
    "$OUT_DIR/M117C1-ch.vcf.gz"

# Filter for PASS variants and extract INFO fields
bcftools view -f PASS -Oz -o "$OUT_DIR/filtered.vcf.gz" "$OUT_DIR/merged.vcf.gz"

# Convert to TSV and extract required columns
bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "$OUT_DIR/filtered.vcf.gz" | \
    sort -k1,1 -k2,2n > "$OUT_DIR/collapsed.tsv"

# Add header
echo -e "sample\tchrom\tpos\tref\talt\taf" > "$OUT_DIR/collapsed.tsv"
tail -n +2 "$OUT_DIR/collapsed.tsv" >> "$OUT_DIR/collapsed.tsv"

exit 0