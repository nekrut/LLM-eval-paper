#!/usr/bin/env bash
set -euo pipefail

THREADS=4
RAW_DIR="data/raw"
REF_DIR="data/ref"
OUT_DIR="results"

mkdir -p "$OUT_DIR"

# Index reference
if [ ! -f "$REF_DIR/chrM.fa.bwt" ]; then
    bwa index "$REF_DIR/chrM.fa"
fi
if [ ! -f "$REF_DIR/chrM.fa.fai" ]; then
    samtools faidx "$REF_DIR/chrM.fa"
fi

SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

# Alignment and Sorting
for SAMPLE in "${SAMPLES[@]}"; do
    # Alignment
    if [ ! -f "$OUT_DIR/${SAMPLE}.bam" ]; then
        bwa mem -t "$THREADS" "$REF_DIR/chrM.fa" "$RAW_DIR/${SAMPLE}_1.fq.gz" "$RAW_DIR/${SAMPLE}_2.fq.gz" | \
        samtools view -b - > "$OUT_DIR/${SAMPLE}.bam"
    fi

    # Sorting and Indexing
    if [ ! -f "$OUT_DIR/${SAMPLE}.bam.bai" ]; then
        samtools sort -@ "$THREADS" -o "$OUT_DIR/${SAMPLE}.sorted.bam" "$OUT_DIR/${SAMPLE}.bam"
        samtools index "$OUT_DIR/${SAMPLE}.sorted.bam"
        mv "$OUT_DIR/${SAMPLE}.sorted.bam" "$OUT_DIR/${SAMPLE}.bam"
    fi
done

# Variant Calling
for SAMPLE in "${SAMPLES[@]}"; do
    if [ ! -f "$OUT_DIR/${SAMPLE}.vcf.gz" ]; then
        lofreq call-parallel -f "$REF_DIR/chrM.fa" -o "$OUT_DIR/${SAMPLE}.vcf.gz" -m lofreq-mpileup -t "$THREADS" "$OUT_DIR/${SAMPLE}.bam"
    fi
done

# VCF Indexing
for SAMPLE in "${SAMPLES[@]}"; do
    if [ ! -f "$OUT_DIR/${SAMPLE}.vcf.gz.tbi" ]; then
        tabix -p vcf "$OUT_DIR/${SAMPLE}.vcf.gz"
    fi
done

# Collapsing
if [ ! -f "$OUT_DIR/collapsed.tsv" ]; then
    > "$OUT_DIR/collapsed.tsv"
    for SAMPLE in "${SAMPLES[@]}"; do
        bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "$OUT_DIR/${SAMPLE}.vcf.gz" | \
        awk -v s="$SAMPLE" '{print s"\t"$0}' >> "$OUT_DIR/collapsed.tsv"
    fi
fi