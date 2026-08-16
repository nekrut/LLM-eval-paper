#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES="M117-bl M117-ch M117C1-bl M117C1-ch"

REF="data/ref/chrM.fa"

mkdir -p results

# --- Reference indexing (once) ---
if [ ! -f "${REF}.fai" ]; then
  samtools faidx "${REF}"
fi

if [ ! -f "${REF}.bwt" ] || [ ! -f "${REF}.amb" ] || [ ! -f "${REF}.ann" ] || [ ! -f "${REF}.pac" ] || [ ! -f "${REF}.sa" ]; then
  bwa index "${REF}"
fi

# --- Per-sample processing ---
for sample in $SAMPLES; do
  FQ1="data/raw/${sample}_1.fq.gz"
  FQ2="data/raw/${sample}_2.fq.gz"
  BAM="results/${sample}.bam"
  BAI="results/${sample}.bam.bai"
  VCF="results/${sample}.vcf"
  VCFGZ="results/${sample}.vcf.gz"
  TBI="results/${sample}.vcf.gz.tbi"

  if [ ! -f "$BAM" ] || [ "$FQ1" -nt "$BAM" ] || [ "$FQ2" -nt "$BAM" ]; then
    bwa mem -t "$THREADS" -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" "$REF" "$FQ1" "$FQ2" \
      | samtools sort -@ "$THREADS" -o "$BAM" -
  fi

  if [ ! -f "$BAI" ] || [ "$BAM" -nt "$BAI" ]; then
    samtools index -@ "$THREADS" "$BAM"
  fi

  if [ ! -f "$VCFGZ" ] || [ "$BAM" -nt "$VCFGZ" ]; then
    rm -f "$VCF" "$VCFGZ"
    lofreq call-parallel --pp-threads "$THREADS" --verbose --ref "$REF" --out "$VCF" "$BAM"
    bgzip -f "$VCF"
  fi

  if [ ! -f "$TBI" ] || [ "$VCFGZ" -nt "$TBI" ]; then
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
  {
    printf 'sample\tchrom\tpos\tref\talt\taf\n'
    for sample in $SAMPLES; do
      bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "results/${sample}.vcf.gz"
    done
  } > "$COLLAPSED"
fi