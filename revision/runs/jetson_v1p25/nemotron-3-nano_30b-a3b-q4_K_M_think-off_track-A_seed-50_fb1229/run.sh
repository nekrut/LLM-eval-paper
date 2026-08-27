#!/usr/bin/env bash
set -euo pipefail
THREADS=4
mkdir -p results
samples=(M117-bl M117-ch M117C1-bl M117C1-ch)
for sample in "${samples[@]}"; do
  if [[ ! -f "results/${sample}.vcf.gz.tbi" ]]; then
    if [[ ! -f "data/ref/chrM.fa.fai" ]]; then
      samtools faidx data/ref/chrM.fa
    fi
    if [[ ! -f "data/ref/chrM.fa.amb" ]]; then
      bwa index data/ref/chrM.fa
    fi
    readgroup="@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA"
    bwa mem -t "${THREADS}" -R "${readgroup}" data/ref/chrM.fa \
      "data/raw/${sample}_1.fq.gz" "data/raw/${sample}_2.fq.gz" |
      samtools sort -@ "${THREADS}" -o "results/${sample}.bam"
    samtools index -@ "${THREADS}" "results/${sample}.bam"
    lofreq call-parallel --pp-threads "${THREADS}" -f data/ref/chrM.fa \
      -o "results/${sample}.vcf" "results/${sample}.bam"
    bgzip -c "results/${sample}.vcf" > "results/${sample}.vcf.gz"
    tabix -p vcf "results/${sample}.vcf.gz"
    rm -f "results/${sample}.vcf"
  fi
done
if [[ ! -s results/collapsed.tsv || any newer than collapsed.tsv ]]; then
  {
    printf 'sample\tchrom\tpos\tref\talt\taf\n'
    for sample in "${samples[@]}"; do
      bcftools query -f '{sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' \
        "results/${sample}.vcf.gz"
    done
  } > results/collapsed.tsv.tmp && mv results/collapsed.tsv.tmp results/collapsed.tsv
exit 0