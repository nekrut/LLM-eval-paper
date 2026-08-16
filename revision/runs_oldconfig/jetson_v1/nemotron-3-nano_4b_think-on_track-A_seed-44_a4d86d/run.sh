#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES="M117-bl M117-ch M117C1-bl M117C1-ch"

mkdir -p results

if [ ! -f data/ref/chrM.fa.ind ] || [ ! -f data/ref/chrM.amb ]; then
 samtools faidx data/ref/chrM.fa
 bwa index data/ref/chrM.fa
fi

for sample in $SAMPLES; do
 bam_out="results/${sample}.bam"
 bai_out="${bam_out}.bai"
 vcf_tmp="results/${sample}.vcf"

 bwa mem -t $THREADS data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz \
  -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" | samtools sort -@ $THREADS -o "$bam_out"

 samtools index -@ $THREADS "$bam_out"

 lofreq call-parallel --pp-threads $THREADS \
   -r data/ref/chrM.fa \
   -i "$bam_out" \
   -o "$vcf_tmp"

 bgzip -c "$vcf_tmp" > "results/${sample}.vcf.gz"
 tabix -p vcf results/${sample}.vcf.gz

 rm "$vcf_tmp"

 if [ ! -f results/collapsed.tsv ] || [ "$(stat -c %Y results/collapsed.tsv)" -lt "$(stat -c %Y results/${sample}.vcf.gz)" ]; then
   bcftools query -f '{sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "results/${sample}.vcf.gz" >> results/collapsed.tsv
 fi

 if [ ! -f results/collapsed.tsv ] || [ "$(head -n1 results/collapsed.tsv)" != "sample\tchrom\tpos\tref\talt\taf" ]; then
   echo "sample\tchrom\tpos\tref\talt\taf" > results/collapsed.tsv
 fi

done