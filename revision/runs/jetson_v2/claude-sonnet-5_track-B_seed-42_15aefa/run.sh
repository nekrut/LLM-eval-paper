#!/usr/bin/env bash
set -euo pipefail

THREADS=4
REF="data/ref/chrM.fa"
RESULTS="results"
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)

mkdir -p "$RESULTS"

# --- reference indexing (idempotent) ---
if [ ! -s "${REF}.bwt" ]; then
  bwa index "$REF"
fi
if [ ! -s "${REF}.fai" ]; then
  samtools faidx "$REF"
fi

# --- per-sample alignment and variant calling ---
for sample in "${SAMPLES[@]}"; do
  R1="data/raw/${sample}_1.fq.gz"
  R2="data/raw/${sample}_2.fq.gz"
  BAM="${RESULTS}/${sample}.bam"
  BAI="${RESULTS}/${sample}.bam.bai"
  RAW_VCF="${RESULTS}/${sample}.raw.vcf"
  VCF="${RESULTS}/${sample}.vcf.gz"
  TBI="${RESULTS}/${sample}.vcf.gz.tbi"

  if [ ! -s "$BAM" ] || [ ! -s "$BAI" ]; then
    bwa mem -t "$THREADS" \
      -R "@RG\tID:${sample}\tSM:${sample}\tPL:ILLUMINA" \
      "$REF" "$R1" "$R2" \
      | samtools sort -@ "$THREADS" -o "$BAM" -
    samtools index "$BAM"
  fi

  if [ ! -s "$VCF" ] || [ ! -s "$TBI" ]; then
    rm -f "$RAW_VCF"
    lofreq call-parallel --pp-threads "$THREADS" -f "$REF" -o "$RAW_VCF" "$BAM"
    bcftools view -Oz -o "$VCF" "$RAW_VCF"
    tabix -f -p vcf "$VCF"
    rm -f "$RAW_VCF"
  fi
done

# --- collapsed table across all samples ---
COLLAPSED="${RESULTS}/collapsed.tsv"
if [ ! -s "$COLLAPSED" ]; then
  TMP_COLLAPSED="${RESULTS}/.collapsed.tsv.tmp"
  {
    printf 'sample\tchrom\tpos\tref\talt\taf\n'
    for sample in "${SAMPLES[@]}"; do
      VCF="${RESULTS}/${sample}.vcf.gz"
      bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "$VCF" \
        | awk -v s="$sample" -F'\t' 'BEGIN{OFS="\t"}{print s,$1,$2,$3,$4,$5}'
    done
  } > "$TMP_COLLAPSED"
  mv "$TMP_COLLAPSED" "$COLLAPSED"
fi