#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)
REF=data/ref/chrM.fa
RAW=data/raw
OUT=results

mkdir -p "$OUT"

if [[ ! -f "${REF}.fai" || ! -f "${REF}.bwt" ]]; then
  samtools faidx "$REF"
  bwa index "$REF"
fi

for s in "${SAMPLES[@]}"; do
  bam="$OUT/$s.bam"
  bai="$bam.bai"
  vcf="$OUT/$s.vcf.gz"
  tbi="$vcf.tbi"
  r1="$RAW/${s}_1.fq.gz"
  r2="$RAW/${s}_2.fq.gz"

  if [[ -f "$tbi" ]]; then
    continue
  fi

  bwa mem -t "$THREADS" \
    -R "@RG\tID:$s\tSM:$s\tLB:$s\tPL:ILLUMINA" \
    "$REF" "$r1" "$r2" | samtools sort -@ "$THREADS" -o "$bam"

  samtools index -@ "$THREADS" "$bam"

  lofreq call-parallel --pp-threads "$THREADS" \
    --ref "$REF" --out "$OUT/$s.vcf" \
    "$bam"

  bgzip -c "$OUT/$s.vcf" > "$vcf"
  rm -f "$OUT/$s.vcf"
  tabix -p vcf "$vcf"
done

tsv="$OUT/collapsed.tsv"
need=0
if [[ ! -f "$tsv" ]]; then
  need=1
else
  for s in "${SAMPLES[@]}"; do
    if [[ "$OUT/$s.vcf.gz.tbi" -nt "$tsv" ]]; then
      need=1
      break
    fi
  done
fi

if [[ $need -eq 1 ]]; then
  {
    printf 'sample\tchrom\tpos\tref\talt\taf\n'
    for s in "${SAMPLES[@]}"; do
      bcftools query -h "$OUT/$s.vcf.gz" | grep -v '^#' || true
      bcftools query -F "AF" -f "{$s}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "$OUT/$s.vcf.gz"
    done
  } > "$tsv"
fi