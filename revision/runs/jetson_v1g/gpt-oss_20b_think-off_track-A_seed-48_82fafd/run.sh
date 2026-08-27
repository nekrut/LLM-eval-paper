#!/usr/bin/env bash
set -euo pipefail

THREADS=4
RESULTS="results"
REF_DIR="data/ref"
RAW_DIR="data/raw"

SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

mkdir -p "$RESULTS"

# Reference indexing (once)
if [ ! -f "${REF_DIR}/chrM.fa.fai" ]; then
  samtools faidx "${REF_DIR}/chrM.fa"
fi
if [ ! -f "${REF_DIR}/chrM.fa.amb" ]; then
  bwa index "${REF_DIR}/chrM.fa"
fi

# Per-sample processing
for sample in "${SAMPLES[@]}"; do
  bam="${RESULTS}/${sample}.bam"
  bai="${bam}.bai"

  # Alignment and sorting (skip if BAM index exists)
  if [ ! -f "$bai" ]; then
    bwa mem -t "$THREADS" \
      -R "@RG\\tID:${sample}\\tSM:${sample}\\tLB:${sample}\\tPL:ILLUMINA" \
      "${RAW_DIR}/${sample}_1.fq.gz" "${RAW_DIR}/${sample}_2.fq.gz" |
      samtools sort -@ "$THREADS" -o "$bam"
    samtools index -@ "$THREADS" "$bam"
  fi

  vcf="${RESULTS}/${sample}.vcf"
  vcfz="${vcf}.gz"
  tbi="${vcfz}.tbi"

  # Variant calling (skip if compressed VCF index exists)
  if [ ! -f "$tbi" ]; then
    lofreq call-parallel --pp-threads "$THREADS" --verbose \
      --ref "${REF_DIR}/chrM.fa" --out "$vcf" \
      --sig --bonf "$bam"
    samtools view -O z -o "$vcfz" "$vcf"
    tabix -p vcf "$vcfz"
    rm "$vcf"
  fi
done

# Collapse step
collapsed="${RESULTS}/collapsed.tsv"

needs_collapsed=false
if [ ! -f "$collapsed" ]; then
  needs_collapsed=true
else
  for sample in "${SAMPLES[@]}"; do
    vcfz="${RESULTS}/${sample}.vcf.gz"
    if [ -f "$vcfz" ] && [ "$vcfz" -nt "$collapsed" ]; then
      needs_collapsed=true
      break
    fi
  done
fi

if $needs_collapsed; then
  tmp=$(mktemp)
  printf "sample\tchrom\tpos\tref\talt\taf\n" > "$tmp"
  for sample in "${SAMPLES[@]}"; do
    vcfz="${RESULTS}/${sample}.vcf.gz"
    if [ -f "$vcfz" ]; then
      bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "$vcfz" >> "$tmp"
    fi
  done
  mv "$tmp" "$collapsed"
fi

exit 0