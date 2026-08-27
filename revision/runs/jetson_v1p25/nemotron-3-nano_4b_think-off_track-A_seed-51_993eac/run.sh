#!/usr/bin/env bash
set -euo pipefail
THREADS=4
SAMPLES="M117-bl M117-ch M117C1-bl M117C1-ch"
mkdir -p results
for S in $SAMPLES; do
  if [ ! -f "results/${S}.bam" ] || [ ! -f "data/raw/${S}_2. fq.gz" ]; then
    bwa mem -t $THREADS data/raw/${S}_1.fq.gz data/raw/${S}_2.fq.gz > results/${S}.bam 2>/dev/null
  fi
done
for S in $SAMPLES; do
  if [ ! -f "results/${S}.bam. bai" ] || [ ! -f "results/${S}.bam" ]; then
    samtools sort -@ $THREADS -o results/${S}.bam data/raw/${S}_1.fq.gz data/raw/${S}_2.fq.gz 2>/dev/null
  fi
done
for S in $SAMPLES; do
  if [ ! -f "results/${S}.bam. bai" ] || [ ! -f "results/${S}.bam" ]; then
    samtools index -@ $THREADS results/${S}.bam 2>/dev/null
  fi
done
for S in $SAMPLES; do
  if [ ! -f "results/${S}.vcf.gz.tbi" ] || [ ! -f "results/${S}.vcf" ]; then
    lofreq call-parallel --pp-threads $THREADS -f data/ref/chrM.fa -o results/${S}.vcf results/${S}.bam 2>/dev/null
    bgzip results/${S}.vcf > results/${S}.vcf.gz
    tabix -p vcf results/${S}.vcf.gz > results/${S}.vcf.gz.tbi
    rm results/${S}.vcf
  fi
done
for S in $SAMPLES; do
  if [ ! -f "results/collapsed. tsv" ] || [ ! -f "results/${S}.vcf.gz" ]; then
    bcftools query -f "${S}\\t%CHROM\\t%POS\\t%REF\\t%ALT\\t%INFO/AF\\n" results/${S}.vcf.gz | cat > results/collapsed. tsv 2>/dev/null
    echo "sample\\tchrom\\tpos\\tref\\taltaf" >> results/collapsed. tsv
  fi
done
exit 0