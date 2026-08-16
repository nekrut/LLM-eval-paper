#!/usr/bin/env bash
set -euo pipefail

THREADS=4

# Ensure results directory exists
mkdir -p results

# Index reference if not already indexed
if [ ! -f data/ref/chrM.fa.bwt ]; then
  bwa index data/ref/chrM.fa
fi

samples=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

for sample in "${samples[@]}"; do
  # Map reads to reference and sort BAM if not already done
  if [ ! -s results/${sample}.bam ]; then
    bwa mem -t "$THREADS" data/ref/chrM.fa data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz |
      samtools view -bS - | samtools sort -o results/${sample}.bam
  fi

  # Index BAM if not already indexed
  if [ ! -s results/${sample}.bam.bai ]; then
    samtools index results/${sample}.bam
  fi

  # Call variants with lofreq if VCF not already produced
  if [ ! -s results/${sample}.vcf.gz ]; then
    lofreq call -f data/ref/chrM.fa -o tmp.vcf results/${sample}.bam
    bgzip -c tmp.vcf > results/${sample}.vcf.gz
    rm tmp.vcf
  fi

  # Index VCF if not already indexed
  if [ ! -s results/${sample}.vcf.gz.tbi ]; then
    tabix -p vcf results/${sample}.vcf.gz
  fi
done

# Create collapsed table if it does not exist
if [ ! -s results/collapsed.tsv ]; then
  > results/collapsed.tsv.tmp
  printf "sample\tchrom\tpos\tref\talt\taf\n" >> results/collapsed.tsv.tmp
  for sample in "${samples[@]}"; do
    bcftools query -f '%SAMPLE\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' results/${sample}.vcf.gz >> results/collapsed.tsv.tmp
  done
  mv results/collapsed.tsv.tmp results/collapsed.tsv
fi

exit 0