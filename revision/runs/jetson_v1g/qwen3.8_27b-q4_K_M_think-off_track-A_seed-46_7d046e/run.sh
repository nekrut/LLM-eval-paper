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

  if [[ ! -f "$bai" || "$r1" -nt "$bam" || "$r2" -nt "$bam" ]]; then
    bwa mem -t "$THREADS" \
      -R "@RG\tID:${s}\tSM:${s}\tLB:${s}\tPL:ILLUMINA" \
      "$REF" "$r1" "$r2" | samtools sort -@ "$THREADS" -o "$bam"
  fi

  if [[ ! -f "$bai" || "$bam" -nt "$bai" ]]; then
    samtools index -@ "$THREADS" "$bam"
  fi

  if [[ ! -f "$tbi" || "$bam" -nt "$vcf" ]]; then
    lofreq call-parallel --pp-threads "$THREADS" \
      --ref "$REF" --out "$OUT/$s.vcf" \
      "$bam"
    bgzip -c "$OUT/$s.vcf" > "$vcf"
    rm -f "$OUT/$s.vcf"
  fi

  if [[ ! -f "$tbi" || "$vcf" -nt "$tbi" ]]; then
    tabix -p vcf "$vcf"
  fi
done

COLLAPSED="$OUT/collapsed.tsv"
need=0
for s in "${SAMPLES[@]}"; do
  if [[ ! -f "$COLLAPSED" || "$OUT/$s.vcf.gz" -nt "$COLLAPSED" ]]; then
    need=1
    break
  fi
done

if [[ $need -eq 1 ]]; then
  {
    printf 'sample\tchrom\tpos\tref\talt\taf\n'
    for s in "${SAMPLES[@]}"; do
      bcftools query -h "$OUT/$s.vcf.gz" > /dev/null
      bcftools query -f "${s}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "$OUT/$s.vcf.gz"
    done
  } > "$COLLAPSED"
fi