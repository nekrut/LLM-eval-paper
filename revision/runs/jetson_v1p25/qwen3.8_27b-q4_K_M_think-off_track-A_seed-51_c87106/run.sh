#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)

mkdir -p results

if [[ ! -f data/ref/chrM.fa.fai ]]; then
  samtools faidx data/ref/chrM.fa
fi
if [[ ! -f data/ref/chrM.fa.pac ]]; then
  bwa index data/ref/chrM.fa
fi

for s in "${SAMPLES[@]}"; do
  if [[ -s "results/${s}.vcf.gz.tbi" && ! "data/raw/${s}_1.fq.gz" -nt "results/${s}.vcf.gz.tbi" ]]; then
    continue
  fi

  bwa mem -t "${THREADS}" \
    -R "@RG\tID:${s}\tSM:${s}\tLB:${s}\tPL:ILLUMINA" \
    data/ref/chrM.fa \
    "data/raw/${s}_1.fq.gz" "data/raw/${s}_2.fq.gz" \
  | samtools sort -@ "${THREADS}" -o "results/${s}.bam"

  samtools index -@ "${THREADS}" "results/${s}.bam"

  lofreq call-parallel --pp-threads "${THREADS}" -f data/ref/chrM.fa -o "results/${s}.vcf" "results/${s}.bam"

  bgzip -c "results/${s}.vcf" > "results/${s}.vcf.gz"
  rm -f "results/${s}.vcf"
  tabix -p vcf "results/${s}.vcf.gz"
done

if [[ ! -f results/collapsed.tsv ]] || \
   [[ -n "$(find data/raw/*.fq.gz results/*.vcf.gz -newer results/collapsed.tsv -print -quit)" ]]; then
  {
    printf 'sample\tchrom\tpos\tref\talt\taf\n'
    for s in "${SAMPLES[@]}"; do
      bcftools query -f "${s}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "results/${s}.vcf.gz"
    done
  } > results/collapsed.tsv
fi