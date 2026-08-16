#!/usr/bin/env bash
set -euo pipefail

THREADS=4
REF=data/ref/chrM.fa
RAW_DIR=data/raw
RESULTS_DIR=results
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)

mkdir -p "$RESULTS_DIR"

required=()
for s in "${SAMPLES[@]}"; do
  required+=("$RESULTS_DIR/${s}.bam")
  required+=("$RESULTS_DIR/${s}.bam.bai")
  required+=("$RESULTS_DIR/${s}.vcf.gz")
  required+=("$RESULTS_DIR/${s}.vcf.gz.tbi")
done
required+=("$RESULTS_DIR/collapsed.tsv")

all_exist=1
for f in "${required[@]}"; do
  if [[ ! -e "$f" ]]; then
    all_exist=0
    break
  fi
done
if (( all_exist )); then
  exit 0
fi

for s in "${SAMPLES[@]}"; do
  fastq1="${RAW_DIR}/${s}_1.fq.gz"
  fastq2="${RAW_DIR}/${s}_2.fq.gz"

  bwa mem -t "$THREADS" -R '@RG\\tID=${s}\\tSM=${s}\\tPL:ILLUMINA' "$REF" "${fastq1}" "${fastq2}" |
    samtools view -@ "$THREADS" -b - > "$RESULTS_DIR/${s}.unsorted.bam"

  samtools sort -@ "$THREADS" -o "$RESULTS_DIR/${s}.bam" "$RESULTS_DIR/${s}.unsorted.bam"
  rm -f "$RESULTS_DIR/${s}.unsorted.bam"

  samtools index -@ "$THREADS" "$RESULTS_DIR/${s}.bam"

  lofreq call --gzip -f "$REF" -b "$RESULTS_DIR/${s}.bam" -o "$RESULTS_DIR/${s}.vcf.gz" --threads "$THREADS"

  tabix -p vcf "$RESULTS_DIR/${s}.vcf.gz"
done

{
  echo -e "sample\tchrom\tpos\tref\talt\taf"
} > "$RESULTS_DIR/collapsed.tsv"

for s in "${SAMPLES[@]}"; do
  bcftools query -f'%CHROM\t%POS\t%REF\t%ALT[\t%AF]\n' "$RESULTS_DIR/${s}.vcf.gz" |
    awk -v sample="$s" '{print sample "\t" $0}' >> "$RESULTS_DIR/collapsed.tsv"
done