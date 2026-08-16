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

samples=(M117-bl M117-ch M117C1-bl M117C1-ch)

for s in "${samples[@]}"; do
  r1="$RAW/${s}_1.fq.gz"
  r2="$RAW/${s}_2.fq.gz"
  bam="$OUT/$s.bam"
  bai="$bam.bai"
  vcf="$OUT/$s.vcf.gz"
  tbi="$vcf.tbi"

  if [[ ! -f "$bai" ]]; then
    bwa mem -t "$THREADS" -R "@RG\tID:$s\tSM:$s" "$REF" "$r1" "$r2" \
      | samtools sort -@ "$THREADS" -o "$bam"
    samtools index "$bam"
  fi

  if [[ ! -f "$tbi" ]]; then
    lofreq call --min-bq 5 --min-mp 0.75 --min-cov 1 \
      -r "$REF" -s "$bam" > "$OUT/$s.vcf"
    bcftools view -Oz -o "$vcf" "$OUT/$s.vcf"
    rm -f "$OUT/$s.vcf"
    tabix -p vcf "$vcf"
  fi
done

{
  printf 'sample\tchrom\tpos\tref\talt\taf\n'
  for s in "${samples[@]}"; do
    bcftools query \
      --no-header \
      -f '%CHROM\t%POS\t%REF\t%ALT[\t%AF]\n' \
      "$OUT/$s.vcf.gz" | awk -v S="$s" 'BEGIN{OFS="\t"} {print S,$1,$2,$3,$4,$5}'
  done
} > "$OUT/collapsed.tsv"