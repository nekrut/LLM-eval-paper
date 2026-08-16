#!/usr/bin/env bash
set -euo pipefail

mkdir -p results

if [ ! -f data/ref/chrM.fa.fai ] || [ ! -f data/ref/chrM.fa.bwt ]; then
  bwa index data/ref/chrM.fa
  samtools faidx data/ref/chrM.fa
fi

SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)

for sample in "${SAMPLES[@]}"; do
  if [ ! -f "results/${sample}.bam" ] || [ ! -f "results/${sample}.bam.bai" ]; then
    bwa mem -t 4 data/ref/chrM.fa "data/raw/${sample}_1.fq.gz" "data/raw/${sample}_2.fq.gz" | \
      samtools sort -@ 4 -o "results/${sample}.bam" -
    samtools index "results/${sample}.bam"
  fi
done

for sample in "${SAMPLES[@]}"; do
  if [ ! -f "results/${sample}.vcf.gz" ] || [ ! -f "results/${sample}.vcf.gz.tbi" ]; then
    lofreq call -f data/ref/chrM.fa -d "results/${sample}.bam" -o "results/${sample}.vcf"
    bcftools view -Oz -o "results/${sample}.vcf.gz" "results/${sample}.vcf"
    tabix "results/${sample}.vcf.gz"
    rm -f "results/${sample}.vcf"
  fi
done

if [ ! -f results/collapsed.tsv ]; then
  printf "sample\tchrom\tpos\tref\talt\taf\n" > results/collapsed.tsv
  for sample in "${SAMPLES[@]}"; do
    bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "results/${sample}.vcf.gz" | \
      sed 's/\t$/\t./' | \
      awk -v s="$sample" '{print s"\t"$0}' >> results/collapsed.tsv
  done
fi