#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
REF="data/ref/chrM.fa"

mkdir -p results

# --- Reference indexing ---
if [[ ! -s "${REF}.bwt" ]]; then
  bwa index "$REF"
fi

if [[ ! -s "${REF}.fai" ]]; then
  samtools faidx "$REF"
fi

# --- Per-sample alignment + variant calling ---
for sample in "${SAMPLES[@]}"; do
  bam="results/${sample}.bam"
  bai="results/${sample}.bam.bai"
  vcf_gz="results/${sample}.vcf.gz"
  tbi="results/${sample}.vcf.gz.tbi"
  fq1="data/raw/${sample}_1.fq.gz"
  fq2="data/raw/${sample}_2.fq.gz"

  if [[ ! -s "$bam" ]]; then
    bwa mem -t "$THREADS" \
      -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
      "$REF" "$fq1" "$fq2" \
      | samtools sort -@ "$THREADS" -o "$bam" -
  fi

  if [[ ! -s "$bai" ]]; then
    samtools index -@ "$THREADS" "$bam"
  fi

  if [[ ! -s "$vcf_gz" ]]; then
    lofreq call-parallel --pp-threads "$THREADS" -f "$REF" -o "results/${sample}.vcf" "$bam"
    bgzip -f "results/${sample}.vcf"
  fi

  if [[ ! -s "$tbi" ]]; then
    tabix -p vcf "$vcf_gz"
  fi
done

# --- Collapsed TSV (regenerated each run, deterministic) ---
printf 'sample\tchrom\tpos\tref\talt\taf\n' > results/collapsed.tsv
for sample in "${SAMPLES[@]}"; do
  vcf_gz="results/${sample}.vcf.gz"
  bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "$vcf_gz" \
    | awk -v s="$sample" 'BEGIN{OFS="\t"}{print s,$0}' >> results/collapsed.tsv
done