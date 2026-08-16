#!/usr/bin/env bash
set -euo pipefail

THREADS=4
REF="data/ref/chrM.fa"
RAW_DIR="data/raw"
OUT_DIR="results"

mkdir -p "$OUT_DIR"

# Index reference if not already indexed
if [[ ! -f "${REF}.bwa.amb" ]]; then
    bwa index "$REF"
fi
if [[ ! -f "${REF}.fai" ]]; then
    samtools faidx "$REF"
fi

SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

for SAMPLE in "${SAMPLES[@]}"; do
    BAM="$OUT_DIR/${SAMPLE}.bam"
    VCF="$OUT_DIR/${SAMPLE}.vcf.gz"
    
    # Alignment and Sorting
    if [[ ! -f "$BAM" ]]; then
        bwa mem -t "$THREADS" "$REF" \
            "$RAW_DIR/${SAMPLE}_1.fq.gz" \
            "$RAW_DIR/${SAMPLE}_2.fq.gz" | \
            samtools sort -@ "$THREADS" -o "$BAM" -
        samtools index "$BAM"
    fi

    # Variant Calling with LoFreq
    if [[ ! -f "$VCF" ]]; then
        lofreq call -i "$BAM" -r "$REF" -o "${SAMPLE}.vcf"
        bgzip -c "${SAMPLE}.vcf" > "$VCF"
        tabix -p vcf "$VCF"
        rm -f "${SAMPLE}.vcf"
    fi
done

# Collapsed table generation
COLLAPSED="$OUT_DIR/collapsed.tsv"
if [[ ! -f "$COLLAPSED" ]]; then
    printf "sample\tchrom\tpos\tref\talt\taf\n" > "$COLLAPSED"
    for SAMPLE in "${SAMPLES[@]}"; do
        VCF="$OUT_DIR/${SAMPLE}.vcf.gz"
        # Extract POS, REF, ALT and calculate AF from INFO field (LoFreq format: AF=0.123)
        bcftools query -f "${SAMPLE}\t%CHROM\t%POS\t%REF\t%ALT\t[%AF]\n" "$VCF" >> "$COLLAPSED"
    done
fi