#!/usr/ bin/env bash
set -euo pipefail

THREADS=4
samples=(M117-bl M117-ch M117C1-bl M117C1-ch)

mkdir -p results

# Reference indexing (once)
if [ ! -f data/ref/chrM.amb ] || [ ! -f data/ref/chrM.ffa ] || [ ! -f data/ref/chrM.an ] || [ ! -f data/ref/chrM.bwt ] || [ ! -f data/ref/chrM.pac ] || [ ! -f data/ref/chrM.sa ]; then
  bwa index -t $THREADS data/ref/chrM.fa
fi

# Per-sample processing
for sample in "${samples[@]}"; do
  # Alignment and sorting
  RG="-R \"@RG\\tID:${sample}\\tSM:${sample}\\tLB:${sample}\\tPL:ILLUMINA\""
  bwa mem -t $THREADS data/raw/${sample}_1. fq.gz data/raw/${sample}_2.fq.gz $RG | samtools sort -@ $THREADS -o results/${sample}.bam

  # Index BAM
  if [ ! -f results/${sample}.bam.bai ] || [ results/${sample}.bam.bai -nt results/${sample}.bam ]; then
    samtools index -@ $THREADS results/${sample}.bam
  fi

  # Variant calling with lofreq call-parallel
  if [ ! -f results/${sample}.vcf ] || [ results/${sample}.vcf -nt results/${sample}.bam ]; then
    lofreq call-parallel --pp-threads $THREADS --verbose \
      --ref data/ref/chrM.fa \
      --out results/${sample}.vcf \
      --sig \
      --bonf \
      results/${sample}.bam
  fi

  # Compress VCF and index
  if [ ! -f results/${sample}.vcf.gz ] || [ results/${sample}.vcf.gz -nt results/${sample}.vcf ]; then
    bgzip -@ $THREADS results/${sample}.vcf > results/${sample}.vcf.gz && rm results/${sample}.vcf
  fi

  if [ ! -f results/${sample}.vcf.gz.tbi ] || [ results/${sample}.vcf.gz.tbi -nt results/${sample}.vcf.gz ]; then
    tabix -p vcf -@ $THREADS results/${sample}.vcf.gz
  fi
done

# Collapse step
tmp_collapsed=$(mktemp)
echo "sample\tchrom\tpos\tref\talt\taf" > "$tmp_collapsed"
for sample in "${samples[@]}"; do
  if [ -f results/${sample}.vcf.gz ]; then
    bcftools query -f '{sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' results/${sample}.vcf.gz >> "$tmp_collapsed"
  fi
done
mv "$tmp_collapsed" results/collapsed.tsv

exit 0