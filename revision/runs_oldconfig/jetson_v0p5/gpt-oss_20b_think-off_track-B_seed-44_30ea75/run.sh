#!/usr/bin/env bash
set -euo pipefail

THREADS=4

samples=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

# Exit if all outputs already exist
all_exist=true
for sample in "${samples[@]}"; do
  for ext in bam bai vcf.gz tbi; do
    if [ ! -f results/${sample}.${ext} ]; then
      all_exist=false
      break 2
    fi
  done
done

if $all_exist && [ -f results/collapsed.tsv ]; then
  exit 0
fi

# Index reference if needed
if [ ! -f data/ref/chrM.fa.bwt ]; then
  bwa index data/ref/chrM.fa
fi

mkdir -p results

for sample in "${samples[@]}"; do
  bam=results/${sample}.bam
  bai=results/${sample}.bai
  vcf=results/${sample}.vcf.gz
  tbi=results/${sample}.tbi

  if [ ! -f "$bam" ] || [ ! -f "$bai" ] || [ ! -f "$vcf" ] || [ ! -f "$tbi" ]; then
    bwa mem -t $THREADS data/ref/chrM.fa data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz | \
      samtools view -bS - | \
      samtools sort -o "$bam"

    samtools index "$bam"

    lofreq call -f data/ref/chrM.fa -i "$bam" -o "$vcf"

    tabix "$vcf"
  fi
done

tmpfile=results/collapsed.tmp
> "$tmpfile"
printf "sample\tchrom\tpos\tref\talt\taf\n" >> "$tmpfile"

for sample in "${samples[@]}"; do
  vcf=results/${sample}.vcf.gz
  while IFS=$'\t' read -r chrom pos ref alt af; do
    printf "%s\t%s\t%