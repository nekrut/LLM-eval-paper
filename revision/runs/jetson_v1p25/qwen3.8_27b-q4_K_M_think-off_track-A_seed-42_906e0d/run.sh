#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)
REF=data/ref/chrM.fa
RAW=data/raw
OUT=results

mkdir -p "$OUT"

if [[ ! -f "${REF}.fai" ]]; then
  samtools faidx "$REF"
fi
if [[ ! -f "${REF}.amb" || ! -f "${REF}.ann" || ! -f "${REF}.bwt" || ! -f "${REF}.pac" || ! -f "${REF}.sa" ]]; then
  bwa index "$REF"
fi

for s in "${SAMPLES[@]}"; do
  bam="$OUT/${s}.bam"
  bai="$OUT/${s}.bam.bai"
  vcf="$OUT/${s}.vcf"
  vcfgz="$OUT/${s}.vcf.gz"
  tbi="$OUT/${s}.vcf.gz.tbi"

  if [[ -f "$tbi" ]]; then
    continue
  fi

  bwa mem -t "$THREADS" \
    -R "@RG\tID:${s}\tSM:${s}\tLB:${s}\tPL:ILLUMINA" \
    "$REF" "${RAW}/${s}_1.fq.gz" "${RAW}/${s}_2.fq.gz" \
  | samtools sort -@ "$THREADS" -o "$bam"

  if [[ ! -f "$bai" ]]; then
    samtools index -@ "$THREADS" "$bam"
  fi

  lofreq call-parallel --pp-threads "$THREADS" -f "$REF" -o "$vcf" "$bam"

  bgzip -c "$vcf" > "${vcfgz}.tmp"
  mv "${vcfgz}.tmp" "$vcfgz"
  rm -f "$vcf"

  tabix -p vcf "$vcfgz"
done

if [[ ! -f "$OUT/collapsed.tsv" ]]; then
  {
    printf 'sample\tchrom\tpos\tref\talt\taf\n'
    for s in "${SAMPLES[@]}"; do
      bcftools query -f "${s}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "$OUT/${s}.vcf.gz"
    done
  } > "$OUT/collapsed.tsv"
fi