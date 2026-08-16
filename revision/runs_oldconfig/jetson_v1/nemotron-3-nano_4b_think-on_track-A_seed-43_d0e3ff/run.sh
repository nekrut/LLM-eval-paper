#!/usr/ bin/env bash
set -euo pipefail

THREADS=4
SAMPLES="M117-bl M117-ch M117C1-bl M117C1-ch"
RESULTS_DIR="results"

mkdir -p "$RESULTS_DIR"

# Reference indexing (idempotent)
if [ ! -f chrM.ffa ] || [ ! -f chrM.fai ]; then
  samtools faidx data/ref/chrM.fa
fi
if [ ! -f chrM.amb ] || [ ! -f chrM.ann ] || [ ! -f chrM.bwt ] || [ ! -f chrM.pac ] || [ ! -f chrM.sa ]; then
  bwa index data/ref/chrM.fa
fi

# Per-sample processing
for S in $SAMPLES; do
  # Alignment & sorting
  if [ ! -f "$RESULTS_DIR/${S}.bam" ]; then
    bwa mem -t $THREADS \
      -R ":@RG\\tID:${S}\\tSM:${S}\\tLB:${S}\\tPL:ILLUMINA" \
      data/raw/${S}_1. fq.gz data/raw/${S}_2.fq.gz | samtools sort -@ $THREADS -o "$RESULTS_DIR/${S}.bam"
  fi
  # BAM indexing
  if [ ! -f "$RESULTS_DIR/${S}.bam.bai" ]; then
    samtools index -@ $THREADS "$RESULTS_DIR/${S}.bam"
  fi

  # Variant calling (idempotent)
  if [ ! -f "$RESULTS_DIR/${S}.vcf" ]; then
    lofreq call-parallel --pp-threads $THREADS \
      --ref data/ref/chrM.fa \
      --input "$RESULTS_DIR/${S}.bam" \
      --output "$RESULTS_DIR/${S}.vcf"
  fi

  # Compression & indexing
  if [ ! -f "$RESULTS_DIR/${S}.vcf.gz" ]; then
    bgzip -c "$RESULTS_DIR/${S}.vcf" > "$RESULTS_DIR/${S}.vcf.gz"
    tabix -p vcf "$RESULTS_DIR/${S}.vcf.gz"
    rm "$RESULTS_DIR/${S}.vcf"
  fi

  # Remove intermediate .bam if not needed further (idempotent)
  if [ ! -f "$RESULTS_DIR/${S}.bam" ]; then
    rm "$RESULTS_DIR/${S}.bam"
  fi
done

# Collapse table (idempotent)
if [ ! -f results/collapsed.tsv ]; then
  {
    echo "sample\tchrom\tpos\tref\talt\taf"
    for S in $SAMPLES; do
      bcftools query -f '{S}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "$RESULTS_DIR/${S}.vcf.gz" >> results/collapsed.tsv
    done
  } fi

exit 0