#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)

mkdir -p results

if [[ ! -f data/ref/chrM.fa.fai ]]; then
  samtools faidx data/ref/chrM.fa
fi
if [[ ! -f data/ref/chrM.fa.amb || ! -f data/ref/chrM.fa.bwt || ! -f data/ref/chrM.fa.pac || ! -f data/ref/chrM.fa.sa ]]; then
  bwa index data/ref/chrM.fa
fi

for sample in "${SAMPLES[@]}"; do
  r1="data/raw/${sample}_1.fq.gz"
  r2="data/raw/${sample}_2.fq.gz"
  bam="results/${sample}.bam"
  bai="${bam}.bai"
  vcf_gz="results/${sample}.vcf.gz"
  tbi="${vcf_gz}.tbi"

  if [[ -s "$bam" && -s "$bai" && -s "$vcf_gz" && -s "$tbi" ]]; then
    continue
  fi

  bwa mem -t "${THREADS}" \
    -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
    data/ref/chrM.fa "$r1" "$r2" | samtools sort -@ "${THREADS}" -o "$bam"

  if [[ ! -s "$bai" ]]; then
    samtools index -@ "${THREADS}" "$bam"
  fi

  lofreq call-parallel --pp-threads "${THREADS}" \
    -f data/ref/chrM.fa \
    -o "results/${sample}.vcf" "$bam"

  bgzip "results/${sample}.vcf"
  rm -f "results/${sample}.vcf"

  if [[ ! -s "$tbi" ]]; then
    tabix -p vcf "$vcf_gz"
  fi
done

need_rebuild=0
for sample in "${SAMPLES[@]}"; do
  vcf_gz="results/${sample}.vcf.gz"
  if [[ results/collapsed.tsv -ot "$vcf_gz" ]]; then
    need_rebuild=1
    break
  fi
done

if [[ ! -s results/collapsed.tsv || "${need_rebuild}" == "1" ]]; then
  {
    printf 'sample\tchrom\tpos\tref\talt\taf\n'
    for sample in "${SAMPLES[@]}"; do
      bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "results/${sample}.vcf.gz"
    done
  } > results/collapsed.tsv
fi