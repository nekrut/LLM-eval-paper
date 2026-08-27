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
if [[ ! -f "${REF}.bwt" ]]; then
  bwa index "$REF"
fi

for s in "${SAMPLES[@]}"; do
  bam="$OUT/$s.bam"
  bai="$bam.bai"
  vcf_gz="$OUT/$s.vcf.gz"
  tbi="$vcf_gz.tbi"
  f1="$RAW/${s}_1.fq.gz"
  f2="$RAW/${s}_2.fq.gz"

  if [[ -f "$tbi" ]]; then
    continue
  fi

  bwa mem -t "$THREADS" \
      -R "@RG\tID:$s\tSM:$s\tLB:$s\tPL:ILLUMINA" \
      "$REF" "$f1" "$f2" | samtools sort -@ "$THREADS" -o "$bam"

  samtools index -@ "$THREADS" "$bam"

  lofreq call-parallel --pp-threads "$THREADS" -f "$REF" -o "$OUT/$s.vcf" "$bam"

  bgzip -c "$OUT/$s.vcf" > "$vcf_gz"
  rm -f "$OUT/$s.vcf"
  tabix -p vcf "$vcf_gz"
done

if [[ ! -f "$OUT/collapsed.tsv" ]]; then
  {
    printf 'sample\tchrom\tpos\tref\talt\taf\n'
    for s in "${SAMPLES[@]}"; do
      bcftools query -h -f '' "$OUT/$s.vcf.gz" >/dev/null 2>&1 || true
      bcftools query -f "$s\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "$OUT/$s.vcf.gz"
    done
  } > "$OUT/collapsed.tsv"
fi