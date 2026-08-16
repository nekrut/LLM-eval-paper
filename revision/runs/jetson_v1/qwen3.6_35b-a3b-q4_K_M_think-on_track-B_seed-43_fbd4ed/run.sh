#!/usr/bin/env bash
set -euo pipefail

mkdir -p results data/ref

[ -f data/ref/chrM.fa.fai ] || samtools faidx data/ref/chrM.fa
[ -f data/ref/chrM.fa.bwt ] || bwa index data/ref/chrM.fa

SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)

for sample in "${SAMPLES[@]}"; do
  bam="results/${sample}.bam"
  bai="${bam}.bai"
  vcf="results/${sample}.vcf.gz"
  tbi="${vcf}.tbi"

  [ -f "$bam" ] || \
    bwa mem -t 4 data/ref/chrM.fa "data/raw/${sample}_1.fq.gz" "data/raw/${sample}_2.fq.gz" | \
    samtools sort -@ 4 -o "$bam" -

  [ -f "$bai" ] || samtools index "$bam"

  [ -f "$vcf" ] || \
    bcftools mpileup -f data/ref/chrM.fa -d 10000 "$bam" | \
    bcftools call -mv -Oz -o "$vcf" -

  [ -f "$tbi" ] || tabix "$vcf"
done

printf 'sample\tchrom\tpos\tref\talt\taf\n' > results/collapsed.tsv
for sample in "${SAMPLES[@]}"; do
  vcf="results/${sample}.vcf.gz"
  bcftools query -f '%SAMPLE\t%CHROM\t%POS\t%REF\t%ALT\t%AF\n' "$vcf" >> results/collapsed.tsv
done