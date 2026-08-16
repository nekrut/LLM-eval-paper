#!/usr/bin/env bash
set -euo pipefail

mkdir -p results

# Index reference if not already indexed
if [[ ! -f data/ref/chrM.fa.amb ]]; then
    bwa index data/ref/chrM.fa
fi

SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

for SAMPLE in "${SAMPLES[@]}"; do
    BAM="results/${SAMPLE}.bam"
    VCF_GZ="results/${SAMPLE}.vcf.gz"

    # Alignment and Sorting
    if [[ ! -f "$BAM" ]]; then
        bwa mem -t 4 data/ref/chrM.fa "data/raw/${SAMPLE}_1.fq.gz" "data/raw/${SAMPLE}_2.fq.gz" | \
        samtools sort -@ 4 -o "$BAM"
    fi

    # Index BAM if missing
    if [[ ! -f "${BAM}.bai" ]]; then
        samtools index "$BAM"
    fi

    # Variant Calling and Compression
    if [[ ! -f "$VCF_GZ" ]]; then
        lofreq call -f data/ref/chrM.fa -b "$BAM" | \
        bcftools view -Oz -o "$VCF_GZ"
        tabix -p vcf "$VCF_GZ"
    fi
done

# Generate collapsed table
echo -e "sample\tchrom\tpos\tref\talt\taf" > results/collapsed.tsv
for SAMPLE in "${SAMPLES[@]}"; do
    VCF_GZ="results/${SAMPLE}.vcf.gz"
    if [[ -f "$VCF_GZ" ]]; then
        bcftools query -f "${SAMPLE}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "$VCF_GZ" >> results/collapsed.tsv
    fi
done