#!/usr/ bin/env bash
set -euo pipefail

THREADS=4
samples="M117-bl M117-ch M117C1-bl M117C1-ch"

mkdir -p results

# reference index once
if [ ! -f data/ref/chrM.fa.fai ] || [ ! -f data/ref/chrM.amb ] || [ ! -f data/ref/chrM.ann ] || [ ! -f data/ref/chrM.bwt ] || [ ! -f data/ref/chrM.pac ] || [ ! -f data/ref/chrM.sa ]; then
  samtools faidx data/ref/chrM.fa
  bwa index data/ref/chrM.fa
fi

for s in $samples; do
  # alignment
  bwa mem -t $THREADS data/raw/${s}_1.fq.gz data/raw/${s}_2.fq.gz \
    -R "@RG\tID:${s}\tSM:${s}\tLB:${s}\tPL:ILLUMINA" | samtools sort -@ $THREADS -o results/${s}.bam

  # index bam
  samtools index -@ $THREADS results/${s}.bam

  # variant calling with lofreq call-parallel
  lofreq call-parallel --pp-threads $THREADS \
    --ref data/ref/chrM.fa \
    --input results/${s}.bam \
    --output results/${s}.vcf \
    --format VCF

  # compress vcf
  bgzip -c results/${s}.vcf > results/${s}.vcf.gz
  tabix -p vcf results/${s}.vcf.gz

  rm results/${s}.vcf
done

# collapse tsv
{
  echo "sample\tchrom\tpos\tref\talt\taf"
  for s in $samples; do
    bcftools query -f '{s}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' results/${s}.vcf.gz >> results/collapsed.tsv
  done
} > results/collapsed.tsv