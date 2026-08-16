#!/usr/bin/env bash
set -euo pipefail

REF="data/ref/chrM.fa"
RAW="data/raw"
OUT="results"
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

mkdir -p "$OUT"

if [[ ! -f "${REF}.amb" ]]; then
  bwa index "$REF"
fi

for S in "${SAMPLES[@]}"; do
  BAM="$OUT/${S}.bam"
  VCF="$OUT/${S}.vcf.gz"

  if [[ ! -f "$BAM" ]]; then
    bwa mem -t 4 -M "$REF" "${RAW}/${S}_1.fq.gz" "${RAW}/${S}_2.fq.gz" \
      | samtools sort -@ 4 -o "$BAM" -
    samtools index "$BAM"
  fi

  if [[ ! -f "$VCF" ]]; then
    lofreq call -f "$REF" -d -o "${OUT}/${S}.vcf" "$BAM"
    bcftools view -Oz -o "$VCF" "${OUT}/${S}.vcf"
    rm -f "${OUT}/${S}.vcf"
    bcftools index "$VCF"
  fi
done

COLLAPSED="$OUT/collapsed.tsv"
if [[ ! -f "$COLLAPSED" ]]; then
  printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$COLLAPSED"
  for S in "${SAMPLES[@]}"; do
    bcftools query -f '%SAMPLE\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "$OUT/${S}.vcf.gz"
  done | awk -F'\t' 'BEGIN{OFS="\t"} {if($6==".") $6="0"; print}' >> "$COLLAPSED"
fi