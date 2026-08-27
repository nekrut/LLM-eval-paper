#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)

mkdir -p results

if [[ ! -f data/ref/chrM.fa.fai ]]; then
  samtools faidx data/ref/chrM.fa
fi
if [[ ! -f data/ref/chrM.fa.amb || ! -f data/ref/chrM.fa.pac || ! -f data/ref/chrM.fa.sa ]]; then
  bwa index data/ref/chrM.fa
fi

for s in "${SAMPLES[@]}"; do
  bam="results/${s}.bam"
  bai="${bam}.bai"
  vcf_gz="results/${s}.vcf.gz"
  tbi="${vcf_gz}.tbi"

  if [[ -f "$tbi" ]]; then
    continue
  fi

  bwa mem -t "${THREADS}" \
    -R "@RG\tID:${s}\tSM:${s}\tLB:${s}\tPL:ILLUMINA" \
    data/ref/chrM.fa \
    "data/raw/${s}_1.fq.gz" "data/raw/${s}_2.fq.gz" \
  | samtools sort -@ "${THREADS}" -o "$bam"

  if [[ ! -f "$bai" ]]; then
    samtools index -@ "${THREADS}" "$bam"
  fi

  lofreq call-parallel --pp-threads "${THREADS}" -f data/ref/chrM.fa -o "results/${s}.vcf" "$bam"

  bgzip -c "results/${s}.vcf" > "$vcf_gz"
  rm -f "results/${s}.vcf"

  tabix -p vcf "$vcf_gz"
done

rebuild=0
for s in "${SAMPLES[@]}"; do
  if [[ ! -f results/collapsed.tsv || "results/${s}.vcf.gz" -nt results/collapsed.tsv ]]; then
    rebuild=1
    break
  fi
done

if [[ "$rebuild" == "1" ]]; then
  {
    printf 'sample\tchrom\tpos\tref\talt\taf\n'
    for s in "${SAMPLES[@]}"; do
      bcftools query -f "${s}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "results/${s}.vcf.gz"
    done
  } > results/collapsed.tsv
fi