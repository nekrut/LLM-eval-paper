#!/usr/ bin/env bash
set -euo pipefail

THREADS=4
SAMPLES="M117-bl M117-ch M117C1-bl M117C1-ch"

mkdir -p results

# Reference indexing (once)
if [[ ! -f data/ref/chrM.fa.fai ]] || [[ ! -f data/ref/chrM.amb ]] || [[ ! -f data/ref/chrM.ann ]] || [[ ! -f data/ref/chrM.bwt ]] || [[ ! -f data/ref/chrM.pac ]] || [[ ! -f data/ref/chrM.sa ]]; then
   samtools faidx data/ref/chrM.fa
   bwa index data/ref/chrM.fa
fi

# Per-sample processing
for sample in $SAMPLES; do
   # Alignment
   bwa mem -t $THREADS -R ":@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz > results/tmp.sam
   samtools sort -@ $THREADS -o results/${sample}.bam < results/tmp.sam
   rm results/tmp.sam
   samtools index -@ $THREADS results/${sample}.bam

   # Variant calling
   lofreq call-parallel --pp-threads 4 --ref data/ref/chrM.fa --input results/${sample}.bam --output results/${sample}.vcf > results/tmp.vcf
   bgzip -@ $THREADS results/${sample}.vcf.gz
   tabix -p vcf -@ $THREADS results/${sample}.vcf.gz.tbi
   rm results/${sample}.vcf

done

# Collapse table
if [[ ! -s results/collapsed.tsv ]]; then
   echo "sample\tchrom\tpos\tref\talt\taf" > results/collapsed.tsv
fi

# Determine if any VCF newer than TSV -> rebuild
if [[ -s results/collapsed.tsv ]]; then
   tsv_ts=$(stat -c %Y results/collapsed.tsv)
else
   tsv_ts=0
fi
latest_vcf=$(stat -c %Y $(ls results/*.vcf.gz 2>/dev/null | sort -n | tail -1) 2>/dev/null)

if [[ $latest_vcf -gt $tsv_ts ]]; then
   echo "sample\tchrom\tpos\tref\talt\taf" > results/collapsed.tsv
   for sample in $SAMPLES; do
       vcf=${sample}.vcf.gz
       bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "$vcf" >> results/collapsed.tsv
   done
fi