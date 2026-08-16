#!/usr/ bin/env bash
set -euo pipefail
for s in M117-* M117C1-* ; do
  bam=results/${s}.bam
  vcf=results/${s}.vcf.gz
  if [ -f "$bam" ] && [ -f "$vcf" ]; then continue; fi
  tmp=${s}_tmp.bam
  bwa mem -t 4 data/ref/chrM.fa ${s}_bl_1.fq.gz ${s}_bl_2.fq.gz > $tmp || true
  samtools view -@ 4 $tmp > $bam
  samtools sort -@ 4 $bam > ${bam}.sorted
  samtools index ${bam}.sorted $bam.bai
  rm $tmp ${bam}.sorted
  lofreq -p 0.05 $bam > results/${s}.vcf || true
  bcftools view -O z -o $vcf results/${s}.vcf
  tabix -p vcf $vcf
done
printf 'sample\tchrom\tpos\tref\talt\taf\n' > results/collapsed.tsv
for s in M117-* M117C1-* ; do
  bcf=results/${s}.vcf.gz
  if [ ! -f "$bcf" ]; then continue; fi
  tail -n +2 $bcf | awk '{print $0}' >> results/collapsed.tsv
done