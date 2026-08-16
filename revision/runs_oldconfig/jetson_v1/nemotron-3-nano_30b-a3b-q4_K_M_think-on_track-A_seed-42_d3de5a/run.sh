#!/usr/bin/env bash
set -euo pipefail

THREADS=4
samples=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

mkdir -p results

if [[ ! -e data/ref/chrM.fa.fai ]]; then
  samtools faidx data/ref/chrM.fa
fi
if [[ ! -e data/ref/chrM.fa.bwt ]]; then
  bwa index data/ref/chrM.fa
fi

for sample in "${samples[@]}"; do
  if [[ -e results/${sample}.bam && -e results/${sample}.bam.bai && -e results/${sample}.vcf.gz.tbi ]]; then
    continue
  fi

  bwa mem -t "$THREADS" -R "@RG\\tID:${sample}\\tSM:${sample}\\tLB:${sample}\\tPL:ILLUMINA" data/ref/chrM.fa data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz |
    samtools sort -@ 4 -o results/${sample}.bam

  samtools index -@ 4 results/${sample}.bam

  lofreq call-parallel --pp-threads 4 -f data/ref/chrM.fa -o results/${sample}.vcf results/${sample}.bam

  samtools bgzip -c results/${sample}.vcf > results/${sample}.vcf.gz
  tabix -p vcf results/${sample}.vcf.gz

  rm -f results/${sample}.vcf
done

if [[ ! -e results/collapsed.tsv ]]; then
  {
    printf "sample\tchrom\tpos\tref\talt\taf\n"
    for sample in "${samples[@]}"; do
      bcftools query -f '{sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "results/${sample}.vcf.gz"
    done
  } > results/collapsed.tsv
fi

exit 0