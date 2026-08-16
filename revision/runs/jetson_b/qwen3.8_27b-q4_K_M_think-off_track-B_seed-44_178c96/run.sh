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
  vcf="$OUT/$s.vcf.gz"

  if [[ ! -f "$bam.bai" ]]; then
    bwa mem -t "$THREADS" -R "@RG\tID:$s\tSM:$s" "$REF" "$r1" "$r2" \
      | samtools sort -@ "$THREADS" -o "$bam"
  fi

  if [[ ! -f "$bam.bai" ]]; then
    samtools index "$bam"
  fi

  if [[ ! -f "$vcf.tbi" ]]; then
    lofreq call --indels -t "$THREADS" -r "$REF" -o "$vcf" "$bam"
    tabix -p vcf "$vcf"
  fi
done

if [[ ! -f "$OUT/collapsed.tsv" ]]; then
  {
    printf 'sample\tchrom\tpos\tref\talt\taf\n'
    for s in "${SAMPLES[@]}"; do
      bcftools query \
        --no-header \
        -f '%CHROM\t%POS\t%REF\t%ALT\t[%AF]\n' \
        "$OUT/$s.vcf.gz" \
      | while IFS=$'\t' read -r chrom pos ref alt af; do
          printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$s" "$chrom" "$pos" "$ref" "$alt" "${af:-0}"
        done
    done
  } > "$OUT/collapsed.tsv"
fi