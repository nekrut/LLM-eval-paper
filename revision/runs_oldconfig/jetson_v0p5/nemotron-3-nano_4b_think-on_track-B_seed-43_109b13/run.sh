#!/usr/bin/env bash
set -euo pipefail

for sample in M117-*; do
  bam=results/${sample}.bam
  vcf=results/${sample}.vcf.gz
  tbi=results/${sample}.vcf.gz.tbi

  if [[ -f $bam && -f $tbi ]]; then
    continue
  fi

  bwa mem data/ref/chrM.fa "${sample}_1.fq.gz" "${sample}_2.fq.gz" > $bam
  samtools index $bam

  lofreq -i $bam -o results/vcf -m chrM.bed > /dev/null

  bcftools view -O z results/vcf > $vcf
  samtools tbi -p $tbi $vcf.gz
done

tmp=$(mktemp)
for sample in M117-*; do
  bcftools query -f "CHROM\tPOS\tREF\tALT" results/${sample}.vcf.gz >> $tmp
done

awk 'NR==FNR{a[$2]=$0; next} {print a[NR]}' <(sort -t$'\t' -k1,1 -k2,2) < $tmp > results/collapsed.tsv
echo -e "sample\tchrom\tpos\tref\talt\taf" >> results/collapsed.tsv

rm $tmp