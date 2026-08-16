#!/usr/bin/env bash
set -euo pipefail

mkdir -p results

REF="data/ref/chrM.fa"
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
THREADS=4

if [ ! -f "${REF}.bwt" ]; then
    bwa index "$REF"
fi

if [ ! -f "${REF}.fai" ]; then
    samtools faidx "$REF"
fi

for S in "${SAMPLES[@]}"; do
    BAM="results/${S}.bam"
    BAI="results/${S}.bam.bai"
    VCF_GZ="results/${S}.vcf.gz"
    TBI="results/${S}.vcf.gz.tbi"

    if [ ! -f "$BAM" ]; then
        bwa mem -t "$THREADS" "$REF" "data/raw/${S}_1.fq.gz" "data/raw/${S}_2.fq.gz" | \
        samtools sort -@ "$THREADS" -o "$BAM" -
    fi

    if [ ! -f "$BAI" ]; then
        samtools index "$BAM"
    fi

    if [ ! -f "$VCF_GZ" ]; then
        lofreq call -f "$REF" -b "$BAM" > "results/${S}.vcf"
        bcftools view -Oz -o "$VCF_GZ" "results/${S}.vcf"
        rm "results/${S}.vcf"
    fi

    if [ ! -f "$TBI" ]; then
        tabix -p vcf "$VCF_GZ"
    fi
done

if [ ! -f results/collapsed.tsv ]; then
    printf "sample\tchrom\tpos\tref\talt\taf\n" > results/collapsed.tsv
    for S in "${SAMPLES[@]}"; do
        bcftools query -f "${S}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "results/${S}.vcf.gz" >> results/collapsed.tsv
    done
fi