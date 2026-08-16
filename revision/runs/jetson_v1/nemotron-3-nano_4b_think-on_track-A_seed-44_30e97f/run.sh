#!/usr/ bin/ env bash
set -euo pipefail
mkdir -p results

# Reference indexing
if [ ! -f data/ref/chrM.fa.fai ] || [ ! -f data/ref/chrM.amb ] || [ ! -f data/ref/chrM.ann ] || [ ! -f data/ref/chrM.bwt ] || [ ! -f data/ref/chrM.pac ] || [ ! -f data/ref/chrM.sa ]; then
  samtools faidx data/ref/chrM.fa
  bwa index data/ref/chrM.fa
fi

samples="M117-bl M117-ch M117C1-bl M117C1-ch"

for s in $samples; do
  rg="@RG\tID:${s}\tSM:${s}\tLB:${s}\tPL:ILLUMINA"
  bwa mem -t 4 -R "$rg" data/raw/${s}_1. fq.gz data/raw/${s}_2.fq.gz | samtools sort -@ 4 -o results/${s}.bam
  samtools index -@ 4 results/${s}.bam

  if [ ! -f results/${s}.vcf.gz ] || [ $(stat -c %Y results/${s}.vcf.gz) -lt $(stat -c %Y results/${s}.bam) ]; then
    lofreq call-parallel --pp-threads 4 data/ref/chrM.fa results/${s}.bam > results/${s}.vcf
    bgzip -c results/${s}.vcf > results/${s}.vcf.gz
    tabix -p vcf results/${s}.vcf.gz
    rm -f results/${s}.vcf
  fi
done

if [ ! -f results/collapsed.tsv ] || [ $(stat -c %Y results/collapsed.tsv) -lt $(stat -c %Y results/M117-bl.vcf.gz) ] || \
   [ $(stat -c %Y results/collapsed.tsv) -lt $(stat -c %Y results/M117-ch.vcf.gz) ] || \
   [ $(stat -c %Y results/collapsed.tsv) -lt $(stat -c %Y results/M117C1-bl.vcf.gz) ] || \
   [ $(stat -c %Y results/collapsed.tsv) -lt $(stat -c %Y results/M117C1-ch.vcf.gz) ]; then
  {
    echo "sample\tchrom\tpos\tref\talt\taf"
    for s in $samples; do
      bcftools query -f "${s}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" results/${s}.vcf.gz
    done
  } > results/collapsed.tsv
fi