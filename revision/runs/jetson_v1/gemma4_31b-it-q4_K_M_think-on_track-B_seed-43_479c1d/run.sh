#!/usr/bin/env bash
set -euo pipefail

# Define samples and reference
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
REF_FA="data/ref/chrM.fa"
THREADS=4

mkdir -p results

# Index reference in results directory to ensure idempotency and avoid modifying data/ref/
if [ ! -f results/chrM.fa.bwt ]; then
    cp "$REF_FA" results/chrM.fa
    bwa index -p chrM results/chrM.fa
fi

for s in "${SAMPLES[@]}"; do
    # Alignment and Sorting
    if [ ! -f "results/${s}.bam" ]; then
        bwa mem -t "$THREADS" results/chrM.fa "data/raw/${s}_1.fq.gz" "data/raw/${s}_2.fq.gz" | \
        samtools sort -@ "$THREADS" -o "results/${s}.bam"
    fi

    # Index BAM
    if [ ! -f "results/${s}.bam.bai" ]; then
        samtools index -@ "$THREADS" "results/${s}.bam"
    fi

    # Variant Calling with LoFreq (optimized for mtDNA)
    if [ ! -f "results/${s}.vcf.gz" ]; then
        lofreq call -f results/chrM.fa -b "results/${s}.bam" > "results/${s}.vcf"
        bcftools view -Oz -o "results/${s}.vcf.gz" "results/${s}.vcf"
        rm "results/${s}.vcf"
    fi

    # Index VCF
    if [ ! -f "results/${s}.vcf.gz.tbi" ]; then
        tabix -p vcf "results/${s}.vcf.gz"
    fi
done

# Collapse results into a single TSV
if [ ! -f results/collapsed.tsv ]; then
    printf "sample\tchrom\tpos\tref\talt\taf\n" > results/collapsed.tsv
    for s in "${SAMPLES[@]}"; do
        if [ -f "results/${s}.vcf.gz" ]; then
            bcftools query -f "${s}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "results/${s}.vcf.gz" >> results/collapsed.tsv
        fi
    done
fi