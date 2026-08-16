#!/usr/ bin/env bash
set -euo pipefail

mkdir -p results

for sample in M117-*; do
    if [[ -f "results/${sample}.bam" && -f "results/${sample}.vcf.gz" ]]; then
        continue
    fi
    samtools fastq data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz -o results/${sample}.bam 2>/dev/null || exit 1
    samtools index results/${sample}.bam
    bcftools view -M - results/${sample}.bam > results/${sample}.vcf
    gzip results/${sample}.vcf && tabix results/${sample}.vcf.gz
done

> results/collapsed.tsv
for sample in M117-*; do
    bcftools view -M - results/${sample}.bam | awk 'NR==2 {print $1 "\t"$2 "\t"$3 "\t"$4 "\t"$5}' >> results/collapsed.tsv
done

printf "sample\tchrom\tpos\tref\talt\taf\n" > tmp && cat results/collapsed.tsv >> tmp && mv tmp results/collapsed.tsv