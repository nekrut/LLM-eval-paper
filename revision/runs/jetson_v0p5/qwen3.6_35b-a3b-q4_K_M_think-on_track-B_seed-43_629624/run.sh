#!/usr/bin/env bash
set -euo pipefail

REF="data/ref/chrM.fa"
RAW_DIR="data/raw"
RES_DIR="results"
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

mkdir -p "$RES_DIR"

if [ ! -f "${REF}.amb" ]; then
  bwa index "$REF"
fi
if [ ! -f "${REF}.fai" ]; then
  samtools faidx "$REF"
fi

for samp in "${SAMPLES[@]}"; do
  BAM="${RES_DIR}/${samp}.bam"
  BAI="${BAM}.bai"
  VCF_GZ="${RES_DIR}/${samp}.vcf.gz"

  if [ ! -f "$BAI" ]; then
    bwa mem -t 4 "$REF" "${RAW_DIR}/${samp}_1.fq.gz" "${RAW_DIR}/${samp}_2.fq.gz" | \
      samtools sort -@ 4 -o "$BAM" -
    samtools index "$BAM"
  fi

  if [ ! -f "$VCF_GZ" ]; then
    lofreq call -f "$REF" "$BAM" -o "${RES_DIR}/${samp}.vcf"
    bcftools view -Oz -o "$VCF_GZ" "${RES_DIR}/${samp}.vcf"
    rm -f "${RES_DIR}/${samp}.vcf"
    tabix "$VCF_GZ"
  fi
done

COLLAPSED="${RES_DIR}/collapsed.tsv"
if [ ! -f "$COLLAPSED" ]; then
  for f in "${RES_DIR}"/*.vcf.gz; do
    sample=$(basename "$f" .vcf.gz)
    bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%AF\n" "$f"
  done | awk 'BEGIN{OFS="\t"; print "sample","chrom","pos","ref","alt","af"} {print}' > "$COLLAPSED"
fi

exit 0