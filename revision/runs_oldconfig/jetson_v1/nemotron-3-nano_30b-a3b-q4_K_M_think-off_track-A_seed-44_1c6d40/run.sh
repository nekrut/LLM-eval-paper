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
    if [[ ! -d "data/ref/chrM.fa.bwa_index" ]]; then
      bwa index data/ref/chrM.fa
    fi
    rg="@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA"
    bwa mem -t "${THREADS}" -R "${rg}" data/ref/chrM.fa \
      "data/raw/${sample}_1.fq.gz" "data/raw/${sample}_2.fq.gz" |
      samtools sort -@ 4 -o "results/${sample}.bam"
    samtools index -@ 4 "results/${sample}.bam"
    lofreq call-parallel --pp-threads "${THREADS}" \
      -r data/ref/chrM.fa \
      -O "results/${sample}.vcf" \
      "results/${sample}.bam"
    bgzip -c "results/${sample}.vcf" > "results/${sample}.vcf.gz"
    tabix -p vcf "results/${sample}.vcf.gz"
    rm -f "results/${sample}.vcf"
  fi
done
if [[ ! -f results/collapsed.tsv || any results/*.vcf.gz -nt results/collapsed.tsv ]]; then
  {
    printf 'sample\tchrom\tpos\tref\talt\taf\n'
    for sample in "${samples[@]}"; do
      bcftools query -f '{sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "results/${sample}.vcf.gz"
    done
  } > results/collapsed.tsv
fi