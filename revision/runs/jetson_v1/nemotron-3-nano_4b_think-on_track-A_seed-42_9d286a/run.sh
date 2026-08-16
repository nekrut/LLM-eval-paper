#!/usr/ bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)
RESULTS_DIR=results

mkdir -p "$RESULTS_DIR"

samtools faidx data/ref/chrM.fa
bwa index data/ref/chrM.fa

for S in "${SAMPLES[@]}"; do
  IN1=data/raw/${S}_1.fq.gz
  IN2=data/raw/${S}_2.fq.gz
  OUT_BAM=results/${S}.bam
  OUT_BAI=results/${S}.bam.bai

  if [[ ! -f "$OUT_BAM" ]] || (( $(stat -c %Y "$OUT_BAM") < $(stat -c %Y "$IN1") )) || (( $(stat -c %Y "$OUT_BAM") < $(stat -c %Y "$IN2") )); then
    bwa mem -t $THREADS "$IN1" "$IN2" \
      -R "@RG\tID:${S}\tSM:${S}\tLB:${S}\tPL:ILLUMINA" | samtools sort -@ $THREADS -o "$OUT_BAM"
  fi

  if [[ ! -f "$OUT_BAI" ]] || (( $(stat -c %Y "$OUT_BAI") < $(stat -c %Y "$OUT_BAM") )); then
    samtools index -@ $THREADS "$OUT_BAM"
  fi

  VCF_TMP=results/${S}.vcf
  if [[ ! -f "$VCF_TMP" ]] || (( $(stat -c %Y "$VCF_TMP") < $(stat -c %Y "$OUT_BAM") )); then
    lofreq call-parallel --pp-threads $THREADS data/ref/chrM.fa "$OUT_BAM" > "$VCF_TMP"
  fi

  if [[ ! -f results/${S}.vcf.gz ]] || (( $(stat -c %Y results/${S}.vcf.gz) < $(stat -c %Y "$VCF_TMP") )); then
    bgzip -c "$VCF_TMP" > results/${S}.vcf.gz
    tabix -p vcf results/${S}.vcf.gz.tbi
    rm "$VCF_TMP"
  fi

done

COLLAPSE=results/collapsed.tsv
if [[ ! -f "$COLLAPSE" ]] || (( $(date +%s -r $COLLAPSE) < $(date +%s -r results/M117-*.vcf.gz) )); then
  tmp=$RESULTS_DIR/tmp_collapsed.tsv
  printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$tmp"
  for S in "${SAMPLES[@]}"; do
    bcftools query -f '{S}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' results/${S}.vcf.gz >> "$tmp"
  done
  mv "$tmp" "$COLLAPSE"
fi