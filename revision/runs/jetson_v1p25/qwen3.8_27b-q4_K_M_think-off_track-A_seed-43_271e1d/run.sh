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
  r1="${RAW}/${s}_1.fq.gz"
  r2="${RAW}/${s}_2.fq.gz"
  bam="$OUT/${s}.bam"
  bai="$OUT/${s}.bam.bai"
  vcf="$OUT/${s}.vcf"
  vcfgz="$OUT/${s}.vcf.gz"
  tbi="$OUT/${s}.vcf.gz.tbi"

  if [[ ! -f "$tbi" ]]; then
    bwa mem -t "$THREADS" \
      -R "@RG\tID:${s}\tSM:${s}\tLB:${s}\tPL:ILLUMINA" \
      "$REF" "$r1" "$r2" | samtools sort -@ "$THREADS" -o "$bam"

    if [[ ! -f "$bai" ]]; then
      samtools index -@ "$THREADS" "$bam"
    fi

    lofreq call-parallel --pp-threads 4 -f "$REF" -o "$vcf" "$bam"

    bgzip -c "$vcf" > "${vcfgz}.tmp"
    mv "${vcfgz}.tmp" "$vcfgz"
    rm -f "$vcf"

    tabix -p vcf "$vcfgz"
  fi
done

if [[ ! -f "$OUT/collapsed.tsv" ]]; then
  {
    printf 'sample\tchrom\tpos\tref\talt\taf\n'
    for s in "${SAMPLES[@]}"; do
      bcftools query -f "${s}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "$OUT/${s}.vcf.gz"
    done
  } > "$OUT/collapsed.tsv"
fi