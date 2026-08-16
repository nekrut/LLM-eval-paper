#!/usr/bin/env bash
set -euo pipefail

THREADS=4
samples=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

# Exit early if all final outputs already exist
missing=0
for s in "${samples[@]}"; do
  for f in results/${s}.bam results/${s}.bam.bai results/${s}.vcf.gz results/${s}.vcf.gz.tbi; do
    if [[ ! -f $f ]]; then missing=1; break; fi
  done
done
if [[ $missing -eq 0 && -f results/collapsed.tsv ]]; then
  exit 0
fi

mkdir -p results

# Index reference if not already indexed
if [[ ! -f data/ref/chrM.fa.bwt ]]; then
  bwa index data/ref/chrM.fa
  samtools faidx data/ref/chrM.fa
fi

# Prepare collapsed.tsv with header
echo -e "sample\tchrom\tpos\tref\talt\taf" > results/collapsed.tsv

for s in "${samples[@]}"; do
  # Skip if BAM already exists (implies downstream files likely exist)
  if [[ -f results/${s}.bam ]]; then
    continue
  fi

  # Map reads and convert to BAM
  bwa mem -t ${THREADS} data/ref/chrM.fa data/raw/${s}_1.fq.gz data/raw/${s}_2.fq.gz \
    | samtools view -@ ${THREADS} -b - > results/${s}.bam

  # Index BAM
  samtools index results/${s}.bam

  # Variant calling with lofreq
  lofreq call -f data/ref/chrM.fa -o results/${s}.vcf.gz results/${s}.bam

  # Index VCF
  tabix -p vcf results/${s}.vcf.gz

  # Append variant lines to collapsed.tsv
  bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t[%AF]\n' results/${s}.vcf.gz \
    | awk -v samp="${s}" '{print samp"\t"$0}' >> results/collapsed.tsv
done