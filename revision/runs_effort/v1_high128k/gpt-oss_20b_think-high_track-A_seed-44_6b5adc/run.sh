#!/usr/bin/env bash
set -euo pipefail

mkdir -p results
THREADS=4

needs_run() {
  local out=$1
  shift
  local inputs=("$@")
  [[ ! -f "$out" ]] && return 0
  for inp in "${inputs[@]}"; do
    if [[ ! -e "$inp" ]]; then
      return 0
    fi
    if [[ "$inp" -nt "$out" ]]; then
      return 0
    fi
  done
  return 1
}

# Reference indexing
if needs_run data/ref/chrM.fa.bwt data/ref/chrM.fa; then
  bwa index data/ref/chrM.fa
fi

if needs_run data/ref/chrM.fa.fai data/ref/chrM.fa; then
  samtools faidx data/ref/chrM.fa
fi

samples=(M117-bl M117-ch M117C1-bl M117C1-ch)

for sample in "${samples[@]}"; do
  raw1="data/raw/${sample}_1.fq.gz"
  raw2="data/raw/${sample}_2.fq.gz"
  bam="results/${sample}.bam"
  bai="results/${sample}.bam.bai"
  vcf="results/${sample}.vcf"
  vcfgz="results/${sample}.vcf.gz"
  tbi="results/${sample}.vcf.gz.tbi"

  if needs_run "$bam" "$raw1" "$raw2"; then
    bwa mem -t $THREADS -R "@RG\\tID:${sample}\\tSM:${sample}\\tLB:${sample}\\tPL:ILLUMINA" data/ref/chrM.fa "$raw1" "$raw2" | samtools sort -@ $THREADS -o "$bam"
  fi

  if needs_run "$bai" "$bam"; then
    samtools index -@ $THREADS "$bam"
  fi

  if needs_run "$tbi" "$bam"; then
    lofreq call-parallel --pp-threads $THREADS -f data/ref/chrM.fa -b "$bam" > "$vcf"
    samtools bgzip -@ $THREADS -c "$vcf" > "$vcfgz"
    tabix -p vcf "$vcfgz"
    rm -f "$vcf"
  fi
done

collapsed="results/collapsed.tsv"
inputs=()
for sample in "${samples[@]}"; do
  inputs+=("results/${sample}.vcf.gz")
done

if needs_run "$collapsed" "${inputs[@]}"; then
  {
    printf 'sample\tchrom\tpos\tref\talt\taf\n'
    for sample in "${samples[@]}"; do
      bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "results/${sample}.vcf.gz"
    done
  } > "$collapsed"
fi