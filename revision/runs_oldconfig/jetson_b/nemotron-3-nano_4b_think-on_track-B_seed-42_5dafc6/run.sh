#!/usr/bin/env bash
set -euo pipefail

mkdir -p results

for prefix in M117-*; do
  sample=${prefix%_*}
  bwa mem data/ref/chrM.fa data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz results/${sample}.bam
  samtools index results/${sample}.bam

  bcftools view -f "chrM:0-16569" results/${sample}.bam | \
    bcftools call -O z -o results/${sample}.vcf.gz > /dev/null

  tabix -p vcf results/${sample}.vcf.gz
done

> results/collapsed.tsv
echo "sample\tchrom\tpos\tref\talt\taf" >> results/collapsed.tsv

for prefix in M117-*; do
  sample=${prefix%_*}
  bcftools query -f "sample\tchr\tpos\tref\talt\taf" results/${sample}.vcf.gz >> results/collapsed.tsv
done