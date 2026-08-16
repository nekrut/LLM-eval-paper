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
  bam="$OUT/$s.bam"
  if [[ ! -f "$bam" || ! -f "$bam.bai" ]]; then
    bwa aln -t "$THREADS" "$REF" "$RAW/${s}_1.fq.gz" > "$s.1.sai"
    bwa aln -t "$THREADS" "$REF" "$RAW/${s}_2.fq.gz" > "$s.2.sai"
    bwa samse "$REF" "$s.1.sai" | samtools view -b - > "$s.1.bam"
    bwa sampe "$REF" "$s.1.sai" "$s.2.sai" "$RAW/${s}_1.fq.gz" "$RAW/${s}_2.fq.gz" \
      | samtools sort -@ "$THREADS" -o "$bam"
    rm -f "$s.1.sai" "$s.2.sai" "$s.1.bam"
  fi
  if [[ ! -f "$bam.bai" ]]; then
    samtools index "$bam"
  fi

  vcf="$OUT/$s.vcf.gz"
  if [[ ! -f "$vcf" || ! -f "$vcf.tbi" ]]; then
    lofreq call --min-bq 10 --min-pl 20 -t "$THREADS" \
      -o "$vcf" -r "$REF" "$bam"
  fi
  if [[ ! -f "$vcf.tbi" ]]; then
    tabix -p vcf "$vcf"
  fi
done

COLLAPSED="$OUT/collapsed.tsv"
if [[ ! -f "$COLLAPSED" ]]; then
  printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$COLLAPSED"
  for s in "${SAMPLES[@]}"; do
    vcf="$OUT/$s.vcf.gz"
    bcftools query -h "$vcf" | grep -v '^##' \
      | sed 's/^#//' \
      | awk -F'\t' -v OFS='\t' -v s="$s" '{print s, $1, $2, $3, $4, $5}' >> "$COLLAPSED"
  done
fi