#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)
REF=data/ref/chrM.fa
RAW=data/raw
OUT=results

mkdir -p "$OUT"

if [[ ! -f "${REF}.fai" || ! -f "${REF}.amb" ]]; then
  samtools faidx "$REF"
fi
if [[ ! -f "${REF}.bwt" || ! -f "${REF}.pac" || ! -f "${REF}.sa" ]]; then
  bwa index "$REF"
fi

for s in "${SAMPLES[@]}"; do
  bam="$OUT/$s.bam"
  bai="$bam.bai"
  vcf_gz="$OUT/$s.vcf.gz"
  tbi="$vcf_gz.tbi"
  r1="$RAW/${s}_1.fq.gz"
  r2="$RAW/${s}_2.fq.gz"

  if [[ ! -f "$tbi" ]]; then
    bwa mem -t "$THREADS" \
      -R "@RG\tID:${s}\tSM:${s}\tLB:${s}\tPL:ILLUMINA" \
      "$REF" "$r1" "$r2" | samtools sort -@ "$THREADS" -o "$bam"
    samtools index -@ "$THREADS" "$bam"

    tmp_vcf="$OUT/$s.vcf.tmp"
    lofreq call-parallel --pp-threads "$THREADS" \
      -f "$REF" "$bam" > "$tmp_vcf"
    bgzip -c "$tmp_vcf" > "$vcf_gz"
    rm -f "$tmp_vcf"
    tabix -p vcf "$vcf_gz"
  fi
done

tsv="$OUT/collapsed.tsv"
need=0
for s in "${SAMPLES[@]}"; do
  if [[ ! -f "$tsv" || "$OUT/$s.vcf.gz" -nt "$tsv" ]]; then
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
  } > "$tsv"
fi