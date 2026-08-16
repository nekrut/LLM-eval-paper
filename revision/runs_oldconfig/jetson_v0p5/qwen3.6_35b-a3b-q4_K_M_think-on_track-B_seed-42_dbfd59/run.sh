#!/usr/bin/env bash
set -euo pipefail

mkdir -p results

if [ ! -f data/ref/chrM.fa.fai ]; then
  samtools faidx data/ref/chrM.fa
fi

SAMPLES="M117-bl M117-ch M117C1-bl M117C1-ch"

for sample in $SAMPLES; do
  if [ ! -f "results/${sample}.vcf.gz.tbi" ]; then
    bwa mem -t 4 data/ref/chrM.fa \
      "data/raw/${sample}_1.fq.gz" \
      "data/raw/${sample}_2.fq.gz" | \
      samtools sort -@ 4 -o "results/${sample}.bam" -

    samtools index "results/${sample}.bam"

    bcftools mpileup -d 1000000 -I -Q 0 data/ref/chrM.fa "results/${sample}.bam" | \
      bcftools call -mv --ploidy 1 -Oz -o "results/${sample}.vcf.gz" --threads 4

    tabix -p vcf "results/${sample}.vcf.gz"
  fi
done

if [ ! -f results/collapsed.tsv ]; then
  {
    printf 'sample\tchrom\tpos\tref\talt\taf\n'
    for sample in $SAMPLES; do
      bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%AF\n' "results/${sample}.vcf.gz" | \
        awk -v s="$sample" '{print s"\t"$0}'
    done
  } | sort -t$'\t' -k2,2 -k3,3n > results/collapsed.tsv
fi