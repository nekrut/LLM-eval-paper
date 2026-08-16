#!/usr/bin/env bash
set -euo pipefail

mkdir -p results

for sample in M117-*; do
  if [[ -f "results/${sample}.bam" && -f "results/${sample}.vcf.gz" ]]; then
    continue
  fi

  bwa mem chrM.fa data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz \
    > results/${sample}.bam

  samtools index results/${sample}.bam

  cat results/${sample}.bam | bcftools mpileup -f chrM.fa -Oz results/${sample}.vcf.gz

  tabix -p vcf results/${sample}.vcf.gz
done

if [[ ! -f results/collapsed.tsv ]]; then
  echo "sample\tchrom\tpos\tref\talt\taf" > results/collapsed.tsv
  bcftools view -c results/*.vcf.gz | \
    awk -F'\t' '{print $2"\t"$3"\t"$4"\t"$5"\t"$6}' >> results/collapsed.tsv
fi