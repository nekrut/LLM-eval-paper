#!/usr/bin/env bash
set -euo pipefail

SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
THREADS=4

mkdir -p results

if [ ! -f results/chrM.fa.bwt ]; then
    cp data/ref/chrM.fa results/chrM.fa
    bwa index results/chrM.fa
    samtools faidx results/chrM.fa
fi

for s in "${SAMPLES[@]}"; do
    if [ ! -f "results/${s}.vcf.gz" ]; then
        bwa mem -t "$THREADS" results/chrM.fa "data/raw/${s}_1.fq.gz" "data/raw/${s}_2.fq.gz" | \
        samtools sort -@ "$THREADS" -o "results/${s}.bam"
        
        samtools index "results/${s}.bam"
        
        lofreq call -f results/chrM.fa -b "results/${s}.bam" > "results/${s}.vcf"
        bcftools view -Oz -o "results/${s}.vcf.gz" "results/${s}.vcf"
        tabix -p vcf "results/${s}.vcf.gz"
        rm "results/${s}.vcf"
    fi
done

printf "sample\tchrom\tpos\tref\talt\taf\n" > results/collapsed.tsv
for s in "${SAMPLES[@]}"; do
    bcftools query -f "${s}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "results/${s}.vcf.gz" >> results/collapsed.tsv
done