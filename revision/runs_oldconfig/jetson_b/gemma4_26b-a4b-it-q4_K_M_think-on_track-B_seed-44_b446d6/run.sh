#!/usr/bin/env bash
set -euo pipefail

mkdir -p results

REF="data/ref/chrM.fa"
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

if [[ ! -f "${REF}.bwt" ]]; then
    bwa index "$REF"
fi

if [[ ! -f "${REF}.fai" ]]; then
    samtools faidx "$REF"
fi

for sample in "${SAMPLES[@]}"; do
    if [[ ! -f "results/${sample}.vcf.gz" ]]; then
        bwa mem -t 4 "$REF" \
            "data/raw/${sample}_1.fq.gz" \
            "data/raw/${sample}_2.fq.gz" | \
        samtools sort -@ 4 -o "results/${sample}.bam" -
        
        samtools index "results/${sample}.bam"

        lofreq call -f "$REF" -o "results/${sample}.vcf" "results/${sample}.bam"
        bcftools view -Oz -o "results/${sample}.vcf.gz" "results/${sample}.vcf"
        tabix -p vcf "results/${sample}.vcf.gz"
    fi
done

echo -e "sample\tchrom\tpos\tref\talt\taf" > results/collapsed.tsv
for sample in "${SAMPLES[@]}"; do
    if [[ -f "results/${sample}.vcf.gz" ]]; then
        bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t[%AF]\n" "results/${sample}.vcf.gz" >> results/collapsed.tsv
    fi
done