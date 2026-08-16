#!/usr/bin/env bash
set -euo pipefail

# Directories
RAW_DIR="data/raw"
REF_DIR="data/ref"
OUT_DIR="results"

# Ensure output directory exists
mkdir -p "$OUT_DIR"

# Index reference if not already done
if [ ! -f "$REF_DIR/chrM.fa.bwt" ]; then
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

    # Skip if outputs already exist
    if [ -f "$bam" ] && [ -f "$bam.bai" ] && [ -f "$vcf" ] && [ -f "$vcf.tbi" ]; then
        return 0
    fi

    # 1. Map reads
    bwa mem -t 4 "$REF_DIR/chrM.fa" "$r1" "$r2" | \
        samtools view -b -F 4 - > "$bam"

    # 2. Sort and index BAM
    samtools sort -@ 2 -o "${bam}.tmp" "$bam"
    mv "${bam}.tmp" "$bam"
    samtools index "$bam"

    # 3. Call variants with lofreq
    lofreq call-parallel -f "$REF_DIR/chrM.fa" -o "$vcf" -m indel -C 20 -q 20 -t 2 "$bam"

    # 4. Index VCF
    tabix -p vcf "$vcf"
}

# Process all samples
process_sample "M117-bl"
process_sample "M117-ch"
process_sample "M117C1-bl"
process_sample "M117C1-ch"

# 5. Collapse VCFs into a single TSV
bcftools concat -a -Oz -o "$OUT_DIR/collapsed.vcf.gz" \
    "$OUT_DIR/M117-bl.vcf.gz" \
    "$OUT_DIR/M117-ch.vcf.gz" \
    "$OUT_DIR/M117C1-bl.vcf.gz" \
    "$OUT_DIR/M117C1-ch.vcf.gz"

# 6. Convert to TSV and extract required columns
bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%AF\n' "$OUT_DIR/collapsed.vcf.gz" | \
    grep -v '^#' > "$OUT_DIR/collapsed.tsv"

exit 0