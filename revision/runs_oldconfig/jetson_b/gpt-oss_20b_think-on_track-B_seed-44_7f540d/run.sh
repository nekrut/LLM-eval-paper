#!/usr/bin/env bash
set -euo pipefail

THREADS=4

# Ensure results directory exists
mkdir -p results

# Index the mitochondrial reference if not already indexed
if [ ! -s data/ref/chrM.fa.fai ]; then
  samtools faidx data/ref/chrM.fa
fi

samples=(M117-bl M117-ch M117C1-bl M117C1-ch)

for sample in "${samples[@]}"; do
  # Map reads to reference and sort into BAM if not already present
  if [ ! -s results/${sample}.bam ]; then
    bwa mem -t "$THREADS" data/ref/chrM.fa \
      data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz | \
      samtools sort -@ "$THREADS" -o results/${sample}.bam
  fi

  # Index BAM if index missing
  if [ ! -s results/${sample}.bam.bai ]; then
    samtools index results/${sample}.bam
  fi

  # Call variants with lofreq and compress/index VCF if not already present
  if [ ! -s results/${sample}.vcf.gz ]; then
    lofreq call -f data/ref/chrM.fa results/${sample}.bam | bgzip > results/${sample}.vcf.gz
    tabix -p vcf results/${sample}.vcf.gz
  fi
done

# Generate collapsed table if not already present
if [ ! -s results/collapsed.tsv ]; then
  echo -e "sample\tchrom\tpos\tref\talt\taf" > results/collapsed.tsv.tmp
  for sample in "${samples[@]}"; do
    bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t[%AF]\n' results/${sample}.vcf.gz | \
      awk -v s="$sample" 'BEGIN{OFS="\t"} {print s, $0}' >> results/collapsed.tsv.tmp
  done
  mv results/collapsed.tsv.tmp results/collapsed.tsv
fi

exit 0