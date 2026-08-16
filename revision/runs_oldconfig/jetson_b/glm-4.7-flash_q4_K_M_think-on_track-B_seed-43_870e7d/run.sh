#!/usr/bin/env bash
set -euo pipefail

RAW_DIR="data/raw"
REF_DIR="data/ref"
OUT_DIR="results"

mkdir -p "$OUT_DIR"

# Index reference if missing
if [ ! -f "$REF_DIR/chrM.fa.bwt" ]; then
    bwa index "$REF_DIR/chrM.fa"
    samtools faidx "$REF_DIR/chrM.fa"
fi

# Process each sample
for SAMPLE in M117-bl M117-ch M117C1-bl M117C1-ch; do
    # Alignment
    if [ ! -f "$OUT_DIR/${SAMPLE}.bam" ]; then
        bwa mem -t 4 "$REF_DIR/chrM.fa" "$RAW_DIR/${SAMPLE}_1.fq.gz" "$RAW_DIR/${SAMPLE}_2.fq.gz" | \
        samtools view -bS - > "$OUT_DIR/${SAMPLE}.bam"
        samtools sort -@ 4 -o "$OUT_DIR/${SAMPLE}.sorted.bam" "$OUT_DIR/${SAMPLE}.bam"
        mv "$OUT_DIR/${SAMPLE}.sorted.bam" "$OUT_DIR/${SAMPLE}.bam"
    fi

    # BAM Index
    if [ ! -f "$OUT_DIR/${SAMPLE}.bam.bai" ]; then
        samtools index "$OUT_DIR/${SAMPLE}.bam"
    fi

    # Variant Calling
    if [ ! -f "$OUT_DIR/${SAMPLE}.vcf.gz" ]; then
        bcftools mpileup -f "$REF_DIR/chrM.fa" -Ou -a AD,DP "$OUT_DIR/${SAMPLE}.bam" | \
        bcftools call -mv -Oz -o "$OUT_DIR/${SAMPLE}.vcf.gz"
        bcftools index "$OUT_DIR/${SAMPLE}.vcf.gz"
    fi
done

# Collapsing
if [ ! -f "$OUT_DIR/collapsed.tsv" ]; then
    bcftools concat -Oz -o "$OUT_DIR/merged.vcf.gz" "$OUT_DIR"/*.vcf.gz
    bcftools index "$OUT_DIR/merged.vcf.gz"
    printf "sample\tchrom\tpos\tref\talt\taf\n" > "$OUT_DIR/collapsed.tsv"
    bcftools view -f PASS "$OUT_DIR/merged.vcf.gz" | bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%AF\t%SAMPLE\n' >> "$OUT_DIR/collapsed.tsv"
fi