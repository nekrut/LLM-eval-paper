#!/usr/bin/env bash
set -euo pipefail

THREADS=4
REF=data/ref/chrM.fa
RAW=data/raw
OUT=results
mkdir -p "$OUT"

if [[ ! -f data/ref/chrM.fa.fai ]]; then
  samtools faidx "$REF"
fi

SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)

for s in "${SAMPLES[@]}"; do
  r1="$RAW/${s}_1.fq.gz"
  r2="$RAW/${s}_2.fq.gz"
  bam="$OUT/$s.bam"
  bai="$OUT/$s.bam.bai"
  vcf="$OUT/$s.vcf.gz"
  tbi="$OUT/$s.vcf.gz.tbi"

  if [[ ! -f "$bam" || ! -f "$bai" ]]; then
    bwa mem -t "$THREADS" -M -R "@RG\tID:$s\tSM:$s" "$REF" "$r1" "$r2" \
      | samtools sort -@ "$THREADS" -o "$bam"
    samtools index "$bam"
  fi

  if [[ ! -f "$vcf" || ! -f "$tbi" ]]; then
    lofreq call --min-bq 5 --min-mp 0.75 \
      -s "$r1" -s "$r2" -b "$bam" -o "$vcf" "$REF"
    tabix -p vcf "$vcf"
  fi
done

if [[ ! -f "$OUT/collapsed.tsv" ]]; then
  {
    printf 'sample\tchrom\tpos\tref\talt\taf\n'
    for s in "${SAMPLES[@]}"; do
      bcftools query \
        --no-header \
        --format '%CHROM\t%POS\t%REF\t%ALT\t[%AF]\n' \
        "$OUT/$s.vcf.gz" | while IFS=$'\t' read -r chrom pos ref alt af; do
          printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$s" "$chrom" "$pos" "$ref" "$alt" "$af"
        done
    done
  } > "$OUT/collapsed.tsv"
fi