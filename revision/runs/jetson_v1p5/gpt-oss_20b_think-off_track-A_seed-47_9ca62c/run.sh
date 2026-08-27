#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
REF="data/ref/chrM.fa"
RESULTS_DIR="results"

mkdir -p "$RESULTS_DIR"

# Exit if all expected outputs already exist
ALL_PRESENT=true
for sample in "${SAMPLES[@]}"; do
  [[ ! -f "$RESULTS_DIR/${sample}.bam" ]] && ALL_PRESENT=false
  [[ ! -f "$RESULTS_DIR/${sample}.bam.bai" ]] && ALL_PRESENT=false
  [[ ! -f "$RESULTS_DIR/${sample}.vcf.gz" ]] && ALL_PRESENT=false
  [[ ! -f "$RESULTS_DIR/${sample}.vcf.gz.tbi" ]] && ALL_PRESENT=false
done
[[ ! -f "$RESULTS_DIR/collapsed.tsv" ]] && ALL_PRESENT=false

if $ALL_PRESENT; then
  exit 0
fi

# Reference indexing
if [[ ! -f "${REF}.bwt" ]]; then
  bwa index "$REF"
fi

if [[ ! -f "${REF}.fai" ]]; then
  samtools faidx "$REF"
fi

for sample in "${SAMPLES[@]}"; do
  BAM="$RESULTS_DIR/${sample}.bam"
  BAI="$BAM.bai"
  VCF="$RESULTS_DIR/${sample}.vcf"
  VCFZ="$VCF.gz"

  # Alignment and sorting
  if [[ ! -f "$BAM" ]]; then
    RG_TAG=$(printf '@RG\tID:%s\tSM:%s\tLB:%s\tPL:ILLUMINA' "$sample" "$sample" "$sample")
    bwa mem -t "$THREADS" -R "$RG_TAG" \
      "$REF" "data/raw/${sample}_1.fq.gz" "data/raw/${sample}_2.fq.gz" |
      samtools sort -@ "$THREADS" -o "$BAM" -
  fi

  # BAM index
  if [[ ! -f "$BAI" ]]; then
    samtools index -@ "$THREADS" "$BAM"
  fi

  # Variant calling and compression
  if [[ ! -f "$VCFZ" ]]; then
    lofreq call-parallel --pp-threads "$THREADS" -f "$REF" -o "$VCF" "$BAM"
    bcftools view -Oz -o "$VCFZ" "$VCF"
    tabix -p vcf "$VCFZ"
  fi
done

# Collapsed TSV
if [[ ! -f "$RESULTS_DIR/collapsed.tsv" ]]; then
  printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$RESULTS_DIR/collapsed.tsv"
  for sample in "${SAMPLES[@]}"; do
    VCFZ="$RESULTS_DIR/${sample}.vcf.gz"
    bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "$VCFZ" |
      awk -v s="$sample" 'BEGIN{OFS="\t"}{print s,$0}' >> "$RESULTS_DIR/collapsed.tsv"
  done
fi

exit 0