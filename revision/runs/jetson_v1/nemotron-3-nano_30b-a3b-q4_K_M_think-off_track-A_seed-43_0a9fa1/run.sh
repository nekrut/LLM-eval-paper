#!/usr/bin/env bash
set -euo pipefail
THREADS=4
mkdir -p results
samples=(M117-bl M117-ch M117C1-bl M117C1-ch)
for sample in "${samples[@]}"; do
  if [[ ! -f "results/${sample}.bam.bai" ]]; then
    bwa mem -t "$THREADS" \
      -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
      data/ref/chrM.fa \
      data/raw/"${sample}"_1.fq.gz \
      data/raw/"${sample}"_2.fq.gz |
    samtools sort -@ "$THREADS" -o "results/${sample}.bam"
  fi
  if [[ ! -f "results/${sample}.bam.bai" ]]; then
    samtools index -@ "$THREADS" "results/${sample}.bam"
  fi
  if [[ ! -f "results/${sample}.vcf.gz.tbi" ]]; then
    lofreq call-parallel --pp-threads "$THREADS" \
      -f data/ref/chrM.fa \
      -o results/"${sample}".vcf \
      results/"${sample}".bam
    bgzip -c "results/${sample}.vcf" > "results/${sample}.vcf.gz"
    tabix -p vcf "results/${sample}.vcf.gz"
    rm -f "results/${sample}.vcf"
  fi
done
if [[ ! -f results/collapsed.tsv ]] || (find data/ref/chrM.fa -newer results/collapsed.tsv > /dev/null); then
  {
    echo -e "sample\tchrom\tpos\tref\talt\taf"
    for sample in "${samples[@]}"; do
      bcftools query -f 'sample\t%CHROM\t%POS\t%REF\t%ALT\t%AF\n' results/"${sample}".vcf.gz | sed "1i ${sample}"
    done
  } > results/collapsed.tsv
fi