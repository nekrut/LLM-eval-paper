#!/usr/bin/env bash
set -euo pipefail

mkdir -p results

# Index reference if needed
if [ ! -f data/ref/chrM.fa.bwt ]; then
    bwa index data/ref/chrM.fa
fi
if [ ! -f data/ref/chrM.fa.fai ]; then
    samtools faidx data/ref/chrM.fa
fi

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)

for sample in "${SAMPLES[@]}"; do
    # Align if BAM doesn't exist
    if [ ! -f "results/${sample}.bam" ]; then
        bwa mem data/ref/chrM.fa "data/raw/${sample}_1.fq.gz" "data/raw/${sample}_2.fq.gz" | \
            samtools sort -@ "${THREADS}" -o "results/${sample}.bam"
    fi

    # Index BAM if needed
    if [ ! -f "results/${sample}.bam.bai" ]; then
        samtools index "results/${sample}.bam"
    fi

    # Call variants if VCF doesn't exist
    if [ ! -f "results/${sample}.vcf.gz" ]; then
        bcftools mpileup -f data/ref/chrM.fa -@ "${THREADS}" "results/${sample}.bam" | \
            bcftools call -mv -Oz -o "results/${sample}.vcf.gz"
    fi

    # Index VCF if needed
    if [ ! -f "results/${sample}.vcf.gz.tbi" ]; then
        tabix -p vcf "results/${sample}.vcf.gz"
    fi
done

# Create collapsed.tsv if it doesn't exist
if [ ! -f results/collapsed.tsv ]; then
    printf "sample\tchrom\tpos\tref\talt\taf\n" > results/collapsed.tsv
    for sample in "${SAMPLES[@]}"; do
        bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT[\t%INFO/AF]\n" "results/${sample}.vcf.gz" >> results/collapsed.tsv
    done
fi