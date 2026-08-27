#!/usr/bin/env bash
set -euo pipefail
THREADS=4
mkdir -p results
samples=(M117-bl M117-ch M117C1-bl M117C1-ch)
for sample in "${samples[@]}"; do
  if [[ -f "results/${sample}.vcf.gz.tbi" ]]; then continue; fi
done
if [[ ! -f data/ref/chrM.fa.fai ]]; then samtools faidx data/ref/chrM.fa; fi
if [[ ! -f data/ref/chrM.fa.amb ]]; then bwa index data/ref/chrM.fa; fi
for sample in "${samples[@]}"; do
  if [[ -f "results/${sample}.bam.bai" ]]; then continue; fi
  fastq1="data/raw/${sample}_1.fq.gz"
  fastq2="data/raw/${sample}_2.fq.gz"
  rg="@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA"
  bwa mem -t "${THREADS}" -R "${rg}" data/ref/chrM.fa "${fastq1}" "${fastq2}" |
    samtools sort -@ "${THREADS}" -o "results/${sample}.bam"
  samtools index -@ "${THREADS}" "results/${sample}.bam"
done
for sample in "${samples[@]}"; do
  if [[ -f "results/${sample}.vcf.gz.tbi" ]]; then continue; fi
  lofreq call-parallel --pp-threads "${THREADS}" --verbose \
    --ref data/ref/chrM.fa --out "results/${sample}.vcf" \
    results/"${sample}".bam
  bgzip -c "results/${sample}.vcf" > "results/${sample}.vcf.gz"
  rm "results/${sample}.vcf"
  tabix -p vcf "results/${sample}.vcf.gz"
done
if [[ ! -f results/collapsed.tsv || any newer than results/*.vcf.gz ]]; then
  {
    printf 'sample\tchrom\tpos\tref\talt\taf\n'
    for sample in "${samples[@]}"; do
      bcftools query -f '{sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "results/${sample}.vcf.gz"
    done
  } | sponge results/collapsed.tsv
fi