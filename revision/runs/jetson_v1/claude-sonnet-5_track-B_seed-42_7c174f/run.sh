#!/usr/bin/env bash
set -euo pipefail

THREADS="${THREADS:-4}"

RAW_DIR="data/raw"
REF_SRC="data/ref/chrM.fa"

RESULTS_DIR="results"
REF_DIR="${RESULTS_DIR}/ref"
TMP_DIR="${RESULTS_DIR}/tmp"
REF="${REF_DIR}/chrM.fa"

mkdir -p "$RESULTS_DIR" "$REF_DIR" "$TMP_DIR"

if [[ ! -s "$REF" ]]; then
  cp "$REF_SRC" "$REF"
fi

if [[ ! -s "${REF}.fai" ]]; then
  samtools faidx "$REF"
fi

if [[ ! -s "${REF}.bwt" ]]; then
  bwa index "$REF"
fi

SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)

for s in "${SAMPLES[@]}"; do
  R1="${RAW_DIR}/${s}_1.fq.gz"
  R2="${RAW_DIR}/${s}_2.fq.gz"

  BAM="${RESULTS_DIR}/${s}.bam"
  BAI="${RESULTS_DIR}/${s}.bam.bai"
  VCF="${RESULTS_DIR}/${s}.vcf.gz"
  TBI="${RESULTS_DIR}/${s}.vcf.gz.tbi"

  SAMPLE_TMP="${TMP_DIR}/${s}"
  mkdir -p "$SAMPLE_TMP"

  if [[ -s "$BAM" && -s "$BAI" && -s "$VCF" && -s "$TBI" ]]; then
    continue
  fi

  if [[ ! -s "$BAM" ]]; then
    bwa mem -t "$THREADS" -R "@RG\tID:${s}\tSM:${s}\tPL:ILLUMINA" "$REF" "$R1" "$R2" \
      | samtools sort -@ "$THREADS" -o "$BAM" -
  fi

  if [[ ! -s "$BAI" ]]; then
    samtools index -@ "$THREADS" "$BAM"
  fi

  IQBAM="${SAMPLE_TMP}/${s}.indelqual.bam"
  if [[ ! -s "$IQBAM" ]]; then
    lofreq indelqual --dindel -f "$REF" -o "$IQBAM" "$BAM"
  fi

  if [[ ! -s "${IQBAM}.bai" ]]; then
    samtools index -@ "$THREADS" "$IQBAM"
  fi

  RAWVCF="${SAMPLE_TMP}/${s}.raw.vcf"
  if [[ ! -s "$RAWVCF" && ! -s "$VCF" ]]; then
    lofreq call --call-indels -f "$REF" -o "$RAWVCF" "$IQBAM"
  fi

  if [[ ! -s "$VCF" ]]; then
    bcftools view -Oz -o "$VCF" "$RAWVCF"
  fi

  if [[ ! -s "$TBI" ]]; then
    tabix -f -p vcf "$VCF"
  fi
done

COLLAPSED="${RESULTS_DIR}/collapsed.tsv"
COLLAPSED_TMP="$(mktemp "${TMP_DIR}/collapsed.XXXXXX")"

printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$COLLAPSED_TMP"

for s in "${SAMPLES[@]}"; do
  VCF="${RESULTS_DIR}/${s}.vcf.gz"
  bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "$VCF" \
    | awk -v s="$s" 'BEGIN{OFS="\t"}{print s,$0}' >> "$COLLAPSED_TMP"
done

mv "$COLLAPSED_TMP" "$COLLAPSED"