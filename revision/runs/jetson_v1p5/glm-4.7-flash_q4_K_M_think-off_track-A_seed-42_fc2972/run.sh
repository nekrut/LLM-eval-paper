#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
mkdir -p results

# 1. Reference indexing
bwa index data/ref/chrM.fa
samtools faidx data/ref/chrM.fa

# 2. Per-sample processing
for sample in "${SAMPLES[@]}"; do
    # Alignment
    bwa mem -t "$THREADS" -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" data/ref/chrM.fa data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz | samtools sort -@ "$THREADS" -o results/${sample}.bam -
    samtools index -@ "$THREADS" results/${sample}.bam
    
    # Variant calling
    lofreq call-parallel --pp-threads "$THREADS" -f data/ref/chrM.fa -o results/${sample}.vcf results/${sample}.bam
    
    # VCF processing
    bgzip -f results/${sample}.vcf
    tabix -p vcf results/${sample}.vcf.gz
    
    # Collapsing
    bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' results/${sample}.vcf.gz | awk -v s="${sample}" 'BEGIN{OFS="\t"}{print s,$0}' >> results/collapsed.tsv
done