#!/usr/bin/env bash
set -euo pipefail

THREADS=4
REF="data/ref/chrM.fa"
RAW="data/raw"
OUT="results"

mkdir -p "$OUT"

# Index reference (idempotent)
if [[ ! -s "${REF}.bwt" ]]; then
  bwa index "$REF"
fi
if [[ ! -s "${REF}.fai" ]]; then
  samtools faidx "$REF"
fi

SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)

for sample in "${SAMPLES[@]}"; do
  R1="${RAW}/${sample}_1.fq.gz"
  R2="${RAW}/${sample}_2.fq.gz"
  BAM="${OUT}/${sample}.bam"
  BAI="${BAM}.bai"
  VCF="${OUT}/${sample}.vcf.gz"
  TBI="${VCF}.tbi"

  if [[ ! -s "$BAM" ]]; then
    bwa mem -t "$THREADS" -R "@RG\tID:${sample}\tSM:${sample}\tPL:ILLUMINA" \
      "$REF" "$R1" "$R2" \
      | samtools sort -@ "$THREADS" -o "$BAM" -
  fi

  if [[ ! -s "$BAI" ]]; then
    samtools index -@ "$THREADS" "$BAM"
  fi

  if [[ ! -s "$VCF" ]]; then
    RAWVCF="${OUT}/${sample}.raw.vcf"
    lofreq call -f "$REF" -o "$RAWVCF" "$BAM"
    bcftools view -Oz -o "$VCF" "$RAWVCF"
    rm -f "$RAWVCF"
  fi

  if [[ ! -s "$TBI" ]]; then
    tabix -f -p vcf "$VCF"
  fi
done

# Build collapsed table (cheap to regenerate; keeps script idempotent)
COLLAPSED="${OUT}/collapsed.tsv"
TMP="${COLLAPSED}.tmp"
printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$TMP"

for sample in "${SAMPLES[@]}"; do
  VCF="${OUT}/${sample}.vcf.gz"
  bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "$VCF" \
    | awk -v s="$sample" 'BEGIN{OFS="\t"}{print s,$1,$2,$3,$4,$5}' >> "$TMP"
done

mv "$TMP" "$COLLAPSED"