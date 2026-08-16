#!/usr/bin/env bash
set -euo pipefail
THREADS=4
SAMPLES="M117-bl M117-ch M117C1-bl M117C1-ch"
mkdir -p results
for S in $SAMPLES; do
  if [[ ! -f "results/${S}.vcf.gz.tbi" ]] || [[ "results/${S}.vcf.gz.tbi" -nt "data/ref/chrM.fa" ]]; then
    samtools faidx data/ref/chrM.fa > /dev/null 2>&1
    bwa index data/ref/chrM.fa > /dev/null 2>&1
  fi
  if [[ ! -f "results/${S}.bam" ]] || [[ "results/${S}.bam" -nt "data/raw/${S}_1.fq.gz" "data/raw/${S}_2.fq.gz" ]]; then
    bwa mem -t $THREADS data/ref/chrM.fa data/raw/${S}_1.fq.gz data/raw/${S}_2.fq.gz 2>/dev/null | samtools sort -@ $THREADS -o results/${S}.bam > /dev/null
    samtools index -@ $THREADS results/${S}.bam > /dev/null
  fi
  if [[ ! -f "results/${S}.vcf" ]] || [[ "results/${S}.vcf" -nt "data/ref/chrM.fa" "results/${S}.bam" ]]; then
    lofreq call-parallel --pp-threads $THREADS data/ref/chrM.fa results/${S}.bam > results/${S}.vcf 2>/dev/null
  fi
  if [[ ! -f "results/${S}.vcf.gz.tbi" ]] || [[ "results/${S}.vcf.gz.tbi" -nt "data/ref/chrM.fa" "results/${S}.vcf" ]]; then
    bgzip results/${S}.vcf > results/${S}.vcf.gz 2>/dev/null
    tabix -p vcf results/${S}.vcf.gz > results/${S}.vcf.gz.tbi 2>/dev/null
    rm results/${S}.vcf 2>/dev/null
  fi
done
for S in $SAMPLES; do
  if [[ ! -f "results/collapsed.tsv" ]] || [[ "results/collapsed.tsv" -nt "data/ref/chrM.fa" "results/${S}.vcf.gz.tbi" ]]; then
    bcftools query -f "${S}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" results/${S}.vcf.gz > results/collapsed.tsv 2>/dev/null
    cat results/collapsed.tsv >> results/collapsed.tsv 2>/dev/null
    echo -e "sample\tchrom\tpos\tref\talt\taf" > results/collapsed.tsv 2>/dev/null
    rm results/collapsed.tsv 2>/dev/null
  fi
done