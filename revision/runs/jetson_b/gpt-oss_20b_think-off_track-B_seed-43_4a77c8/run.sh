#!/usr/bin/env bash
set -euo pipefail

THREADS=4
REF=data/ref/chrM.fa
RESULTS_DIR=results
mkdir -p "$RESULTS_DIR"

# Index reference if needed
if [ ! -f "${REF}.bwt" ]; then bwa index "$REF"; fi
if [ ! -f "${REF}.fai" ]; then samtools faidx "$REF"; fi

samples=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

# Check if all outputs exist
all_present=true
for s in "${samples[@]}"; do
  for ext in bam bai vcf.gz tbi; do
    if [ ! -f "$RESULTS_DIR/${s}.${ext}" ]; then
      all_present=false
      break 2
    fi
  done
done

if $all_present; then
  exit 0
fi

# Process each sample
for s in "${samples[@]}"; do
  fq1=data/raw/"${s}"_1.fq.gz
  fq2=data/raw/"${s}"_2.fq.gz
  bam="$RESULTS_DIR/${s}.bam"
  vcf="$RESULTS_DIR/${s}.vcf"
  vcfgz="$RESULTS_DIR/${s}.vcf.gz"

  if [ ! -f "$bam" ]; then
    bwa mem -t "$THREADS" "$REF" "$fq1" "$fq2" | samtools sort -o "$bam"
  fi

  if [ ! -f "${bam}.bai" ]; then
    samtools index "$bam"
  fi

  if [ ! -f "$vcfgz" ]; then
    lofreq call -f "$REF" -o "$vcf" "$bam"
    bcftools view -O z -o "$vcfgz" "$vcf"
    tabix -p vcf "$vcfgz"
    rm "$vcf"
  fi
done

# Generate collapsed.tsv if missing
collapsed="$RESULTS_DIR/collapsed.tsv"
if [ ! -f "$collapsed" ]; then
  printf "sample\tchrom\tpos\tref\talt\taf\n" > "$collapsed"
  for vcfgz in "$RESULTS_DIR"/*.vcf.gz; do
    s=$(basename "$vcfgz" .vcf.gz)
    bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t[%INFO/AF]\n' "$vcfgz" | awk -v sample="$s" '{print sample"\t"$0}' >> "$collapsed"
  done
fi

exit 0