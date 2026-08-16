#!/usr/bin/env bash
set -euo pipefail

THREADS=4
REF="data/ref/chrM.fa"
RESULTS_DIR="results"

mkdir -p "$RESULTS_DIR"

EXPECTED_FILES=(
"$RESULTS_DIR/M117-bl.bam"
"$RESULTS_DIR/M117-bl.bam.bai"
"$RESULTS_DIR/M117-bl.vcf.gz"
"$RESULTS_DIR/M117-bl.vcf.gz.tbi"
"$RESULTS_DIR/M117-ch.bam"
"$RESULTS_DIR/M117-ch.bam.bai"
"$RESULTS_DIR/M117-ch.vcf.gz"
"$RESULTS_DIR/M117-ch.vcf.gz.tbi"
"$RESULTS_DIR/M117C1-bl.bam"
"$RESULTS_DIR/M117C1-bl.bam.bai"
"$RESULTS_DIR/M117C1-bl.vcf.gz"
"$RESULTS_DIR/M117C1-bl.vcf.gz.tbi"
"$RESULTS_DIR/M117C1-ch.bam"
"$RESULTS_DIR/M117C1-ch.bam.bai"
"$RESULTS_DIR/M117C1-ch.vcf.gz"
"$RESULTS_DIR/M117C1-ch.vcf.gz.tbi"
"$RESULTS_DIR/collapsed.tsv"
)

ALL_PRESENT=true
for f in "${EXPECTED_FILES[@]}"; do
  if [ ! -s "$f" ]; then
    ALL_PRESENT=false
    break
  fi
done

if $ALL_PRESENT; then
  exit 0
fi

if [ ! -e "${REF}.bwt" ]; then
  bwa index "$REF"
fi

SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

for sample in "${SAMPLES[@]}"; do
  BAM="$RESULTS_DIR/${sample}.bam"
  VCF_GZ="$RESULTS_DIR/${sample}.vcf.gz"

  if [ -s "$BAM" ] && [ -s "$VCF_GZ" ]; then
    continue
  fi

  bwa mem -t "$THREADS" "$REF" "data/raw/${sample}_1.fq.gz" "data/raw/${sample}_2.fq.gz" | \
    samtools sort -o "$BAM"

  samtools index "$BAM"

  lofreq call -f "$REF" -o - "$BAM" | bcftools view -Oz > "$VCF_GZ"
  tabix -p vcf "$VCF_GZ"
done

{
  printf "sample\tchrom\tpos\tref\talt\taf\n"
  for sample in "${SAMPLES[@]}"; do
    bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t[%INFO/AF]\n' "$RESULTS_DIR/${sample}.vcf.gz" | \
      awk -v s="$sample" '{print s"\t"$0}'
  done
} > "$RESULTS_DIR/collapsed.tsv"