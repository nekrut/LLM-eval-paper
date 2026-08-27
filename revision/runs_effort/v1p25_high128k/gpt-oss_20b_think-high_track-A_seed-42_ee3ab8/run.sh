#!/usr/bin/env bash
set -euo pipefail

THREADS=4
RESULTS="results"
RAW_DIR="data/raw"
REF_DIR="data/ref"

mkdir -p "$RESULTS"

# Reference indexing
if [ ! -f "${REF_DIR}/chrM.fa.amb" ] || [ ! -f "${REF_DIR}/chrM.fa.fai" ]; then
  samtools faidx "${REF_DIR}/chrM.fa"
  bwa index "${REF_DIR}/chrM.fa"
fi

SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

for sample in "${SAMPLES[@]}"; do
  fq1="${RAW_DIR}/${sample}_1.fq.gz"
  fq2="${RAW_DIR}/${sample}_2.fq.gz"
  bam="${RESULTS}/${sample}.bam"
  bai="${RESULTS}/${sample}.bam.bai"
  vcf="${RESULTS}/${sample}.vcf"
  vcfgz="${RESULTS}/${sample}.vcf.gz"
  tbi="${RESULTS}/${sample}.vcf.gz.tbi"

  # Alignment
  if [ ! -f "$bam" ] || [ "$bam" -ot "$fq1" ] || [ "$bam" -ot "$fq2" ]; then
    bwa mem -t "$THREADS" -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
      "$fq1" "$fq2" | samtools sort -@ "$THREADS" -o "$bam"
  fi

  # BAM index
  if [ ! -f "$bai" ] || [ "$bai" -ot "$bam" ]; then
    samtools index -@ "$THREADS" "$bam"
  fi

  # Variant calling
  if [ ! -f "$tbi" ] || [ "$tbi" -ot "$bam" ]; then
    lofreq call-parallel --pp-threads "$THREADS" -f "${REF_DIR}/chrM.fa" \
      -o "$vcf" "$bam"
    bgzip -c "$vcf" > "$vcfgz"
    tabix -p vcf "$vcfgz"
    rm "$vcf"
  fi
done

# Collapsed table
collapsed="${RESULTS}/collapsed.tsv"

rebuild_collapsed=0
if [ ! -f "$collapsed" ]; then
  rebuild_collapsed=1
else
  for sample in "${SAMPLES[@]}"; do
    vcfgz="${RESULTS}/${sample}.vcf.gz"
    if [ ! -f "$vcfgz" ] || [ "$vcfgz" -nt "$collapsed" ]; then
      rebuild_collapsed=1
      break
    fi
  done
fi

if [ $rebuild_collapsed -eq 1 ]; then
  tmpfile="${RESULTS}/collapsed.tsv.tmp"
  > "$tmpfile"
  printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$tmpfile"
  for sample in "${SAMPLES[@]}"; do
    vcfgz="${RESULTS}/${sample}.vcf.gz"
    bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" \
      "$vcfgz" >> "$tmpfile"
  done
  mv "$tmpfile" "$collapsed"
fi