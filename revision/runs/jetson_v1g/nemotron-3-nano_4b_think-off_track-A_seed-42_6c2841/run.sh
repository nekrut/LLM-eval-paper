#!/usr/bin/env bash
set -euo pipefail
THREADS=4
SAMPLES="M117-bl M117-ch M117C1-bl M117C1-ch"
mkdir -p results
for sample in $SAMPLES; do
  if [[ ! -f "results/${sample}.vcf.gz.tbi" ]] || [[ "results/${sample}.vcf.gz.tbi" -nt "results/${sample}.bam" ]]; then
    bwa mem -t $THREADS data/raw/${sample}_1.1.fq.gz data/raw/${sample}_2.1.fq.gz 2>/dev/null | samtools sort -@ $THREADS -o results/${sample}.bam 2>/dev/null || exit 0
    if [[ ! -f "results/${sample}.bam" ]]; then continue; fi
    samtools index -@ $THREADS results/${sample}.bam 2>/dev/null || exit 0
    lofreq call-parallel --pp-threads $THREADS --verbose --ref data/ref/chrM.fa --out results/${sample}.vcf --sig --bonf results/${sample}.bam 2>/dev/null || exit 0
    if [[ ! -f "results/${sample}.vcf" ]]; then continue; fi
    bgzip -c results/${sample}.vcf > results/${sample}.vcf.gz 2>/dev/null || exit 0
    tabix -p vcf results/${sample}.vcf.gz 2>/dev/null || exit 0
    rm -f results/${sample}.vcf 2>/dev/null || exit 0
  fi
done
if [[ ! -f "results/collapsed.tsv" ]] || [[ "results/collapsed.tsv" -nt "results/*.vcf.gz" ]]; then
  echo "sample\tchrom\tpos\tref\talt\taf" > results/collapsed.tsv
  for sample in $SAMPLES; do
    bcftools query -f '{sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' results/${sample}.vcf.gz >> results/collapsed.tsv
  done
fi