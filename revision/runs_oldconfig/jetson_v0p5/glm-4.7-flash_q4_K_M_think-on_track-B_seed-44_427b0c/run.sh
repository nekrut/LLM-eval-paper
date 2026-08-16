#!/usr/bin/env bash
set -euo pipefail

mkdir -p results

# Index reference if not already done
if [ ! -f data/ref/chrM.fa.amb ]; then
    bwa index data/ref/chrM.fa
fi
if [ ! -f data/ref/chrM.fa.fai ]; then
    samtools faidx data/ref/chrM.fa
fi

# Identify samples
samples=($(ls data/raw/*_1.fq.gz | xargs -n1 basename | sed 's/_1.fq.gz//'))

# Alignment and sorting
for sample in "${samples[@]}"; do
    if [ ! -f "results/${sample}.bam" ]; then
        bwa mem -t 4 data/ref/chrM.fa data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz | \
        samtools view -b - | \
        samtools sort -@ 4 -o "results/${sample}.sorted.bam" - && \
        mv "results/${sample}.sorted.bam" "results/${sample}.bam"
        samtools index "results/${sample}.bam"
    fi
done

# Variant calling
for sample in "${samples[@]}"; do
    if [ ! -f "results/${sample}.vcf.gz" ]; then
        lofreq call -f data/ref/chrM.fa -o "results/${sample}.vcf.gz" -m lofreq -C 50 -q 20 -Q 20 --ploidy 1 --threads 4 "results/${sample}.bam"
        tabix -p vcf "results/${sample}.vcf.gz"
    fi
done

# Collapse results
if [ ! -f "results/collapsed.tsv" ]; then
    bcftools concat -Oz -o results/merged.vcf.gz results/*.vcf.gz
    tabix -p vcf results/merged.vcf.gz
    bcftools query -f '%SAMPLE\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' results/merged.vcf.gz > results/collapsed.tsv
fi