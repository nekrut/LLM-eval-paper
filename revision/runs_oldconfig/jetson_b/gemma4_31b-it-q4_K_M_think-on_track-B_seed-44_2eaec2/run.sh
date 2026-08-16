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

for sample in "${SAMPLES[@]}"; do
    BAM="results/${sample}.bam"
    BAI="results/${sample}.bam.bai"
    VCF_GZ="results/${sample}.vcf.gz"
    TBI="results/${sample}.vcf.gz.tbi"

    if [ ! -f "$BAM" ]; then
        bwa mem -t "$THREADS" "$REF" "data/raw/${sample}_1.fq.gz" "data/raw/${sample}_2.fq.gz" | \
        samtools view -Sb - | \
        samtools sort -@ "$THREADS" -o "$BAM"
    fi

    if [ ! -f "$BAI" ]; then
        samtools index -@ "$THREADS" "$BAM"
    fi

    if [ ! -f "$VCF_GZ" ]; then
        lofreq call -f "$REF" -b "$BAM" > "results/${sample}.vcf"
        bcftools view -Oz -o "$VCF_GZ" "results/${sample}.vcf"
        rm "results/${sample}.vcf"
    fi

    if [ ! -f "$TBI" ]; then
        tabix -p vcf "$VCF_GZ"
    fi
done

printf "sample\tchrom\tpos\tref\talt\taf\n" > results/collapsed.tsv
for sample in "${SAMPLES[@]}"; do
    bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "results/${sample}.vcf.gz" >> results/collapsed.tsv
done