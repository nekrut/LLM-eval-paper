#!/usr/bin/env bash
set -euo pipefail

mkdir -p results

SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
REF="data/ref/chrM.fa"
THREADS=4

if [[ ! -f "${REF}.bwt" ]]; then
    bwa index "$REF"
fi

if [[ ! -f "${REF}.fai" ]]; then
    samtools faidx "$REF"
fi

for sample in "${SAMPLES[@]}"; do
    BAM="results/${sample}.bam"
    VCF_GZ="results/${sample}.vcf.gz"

    if [[ ! -f "$BAM" ]]; then
        bwa mem -t "$THREADS" "$REF" "data/raw/${sample}_1.fq.gz" "data/raw/${sample}_2.fq.gz" | \
        samtools view -u | \
        samtools sort -@ "$THREADS" -o "$BAM"
        samtools index "$BAM"
    fi

    if [[ ! -f "$VCF_GZ" ]]; then
        lofreq call -f "$REF" -b "$BAM" > "results/${sample}.vcf"
        bcftools view -Oz -o "$VCF_GZ" "results/${sample}.vcf"
        tabix -p vcf "$VCF_GZ"
        rm "results/${sample}.vcf"
    fi
done

printf "sample\tchrom\tpos\tref\talt\taf\n" > results/collapsed.tsv
for sample in "${SAMPLES[@]}"; do
    bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "results/${sample}.vcf.gz" >> results/collapsed.tsv
done