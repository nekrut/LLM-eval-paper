#!/usr/bin/env bash
set -euo pipefail

SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
REF="data/ref/chrM.fa"
THREADS=4

mkdir -p results

if [[ ! -f "${REF}.bwt" ]]; then
    bwa index "$REF"
fi

if [[ ! -f "${REF}.fai" ]]; then
    samtools faidx "$REF"
fi

for S in "${SAMPLES[@]}"; do
    BAM="results/${S}.bam"
    BAI="${BAM}.bai"
    VCF="results/${S}.vcf.gz"
    TBI="${VCF}.tbi"

    if [[ ! -f "$BAM" ]]; then
        bwa mem -t "$THREADS" "$REF" "data/raw/${S}_1.fq.gz" "data/raw/${S}_2.fq.gz" | \
        samtools sort -@ "$THREADS" -o "$BAM" -
    fi

    if [[ ! -f "$BAI" ]]; then
        samtools index -@ "$THREADS" "$BAM"
    fi

    if [[ ! -f "$VCF" ]]; then
        lofreq call -f "$REF" -b "$BAM" | \
        bcftools view -Oz -o "$VCF"
    fi

    if [[ ! -f "$TBI" ]]; then
        tabix -p vcf "$VCF"
    fi
done

COLLAPSED="results/collapsed.tsv"
if [[ ! -f "$COLLAPSED" ]]; then
    printf "sample\tchrom\tpos\tref\talt\taf\n" > "$COLLAPSED"
    for S in "${SAMPLES[@]}"; do
        bcftools query -f "${S}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "results/${S}.vcf.gz" >> "$COLLAPSED"
    done
fi