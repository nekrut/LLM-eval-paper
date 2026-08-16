#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
REF="data/ref/chrM.fa"

mkdir -p results

if [[ ! -f "${REF}.bwt" ]]; then
    bwa index "$REF"
fi

if [[ ! -f "${REF}.fai" ]]; then
    samtools faidx "$REF"
fi

for sample in "${SAMPLES[@]}"; do
    BAM="results/${sample}.bam"
    VCF="results/${sample}.vcf.gz"

    if [[ ! -f "$BAM" ]]; then
        bwa mem -t "$THREADS" "$REF" "data/raw/${sample}_1.fq.gz" "data/raw/${sample}_2.fq.gz" | \
        samtools sort -@ "$THREADS" -o "$BAM"
    fi

    if [[ ! -f "${BAM}.bai" ]]; then
        samtools index -@ "$THREADS" "$BAM"
    fi

    if [[ ! -f "$VCF" ]]; then
        lofreq call -f "$REF" -o "results/${sample}.vcf" "$BAM"
        bcftools view -Oz -o "$VCF" "results/${sample}.vcf"
        tabix -p vcf "$VCF"
        rm -f "results/${sample}.vcf"
    fi
done

printf "sample\tchrom\tpos\tref\talt\taf\n" > results/collapsed.tsv
for sample in "${SAMPLES[@]}"; do
    bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "results/${sample}.vcf.gz" >> results/collapsed.tsv
done