#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES="M117-bl M117-ch M117C1-bl M117C1-ch"

mkdir -p results

REF="data/ref/chrM.fa"

# --- Reference indexing (once) ---
if [ ! -f "${REF}.fai" ]; then
  samtools faidx "${REF}"
fi

if [ ! -f "${REF}.amb" ] || [ ! -f "${REF}.ann" ] || [ ! -f "${REF}.bwt" ] \
   || [ ! -f "${REF}.pac" ] || [ ! -f "${REF}.sa" ]; then
  bwa index "${REF}"
fi

# --- Per-sample alignment, indexing, variant calling ---
for sample in $SAMPLES; do
  R1="data/raw/${sample}_1.fq.gz"
  R2="data/raw/${sample}_2.fq.gz"
  BAM="results/${sample}.bam"
  BAI="results/${sample}.bam.bai"
  VCF="results/${sample}.vcf"
  VCFGZ="results/${sample}.vcf.gz"
  TBI="results/${sample}.vcf.gz.tbi"

  if [ ! -f "$BAM" ] || [ "$R1" -nt "$BAM" ] || [ "$R2" -nt "$BAM" ]; then
    bwa mem -t "$THREADS" \
      -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
      "$REF" "$R1" "$R2" \
      | samtools sort -@ "$THREADS" -o "$BAM"
  fi

  if [ ! -f "$BAI" ] || [ "$BAM" -nt "$BAI" ]; then
    samtools index -@ "$THREADS" "$BAM"
  fi

  if [ ! -f "$TBI" ] || [ "$BAM" -nt "$TBI" ]; then
    lofreq call-parallel --pp-threads "$THREADS" --verbose \
      --ref "$REF" --out "$VCF" \
      "$BAM"
    bgzip -f "$VCF"
    tabix -f -p vcf "$VCFGZ"
  fi
done

# --- Collapse step ---
COLLAPSED="results/collapsed.tsv"
NEED_REBUILD=0
if [ ! -f "$COLLAPSED" ]; then
  NEED_REBUILD=1
else
  for sample in $SAMPLES; do
    VCFGZ="results/${sample}.vcf.gz"
    if [ "$VCFGZ" -nt "$COLLAPSED" ]; then
      NEED_REBUILD=1
    fi
  done
fi

if [ "$NEED_REBUILD" -eq 1 ]; then
  TMP=$(mktemp "results/collapsed.tsv.XXXXXX")
  printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$TMP"
  for sample in $SAMPLES; do
    VCFGZ="results/${sample}.vcf.gz"
    bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "$VCFGZ" >> "$TMP"
  done
  mv "$TMP" "$COLLAPSED"
fi