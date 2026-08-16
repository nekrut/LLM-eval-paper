#!/usr/bin/env bash
set -euo pipefail
THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
mkdir -p results

for sample in "${SAMPLES[@]}"; do
    bwa index data/ref/chrM.fa
    samtools faidx data/ref/chrM.fa
    bwa mem -t 4 -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" data/ref/chrM.fa data/raw/${sample}_1.${sample}.fq.gz data/raw/${sample}_2.${sample}.fq.gz | samtools sort -@ 4 -o results/${sample}.bam -
    samtools index -@ 4 results/${sample}.bam
    lofreq call-parallel --pp-threads 4 -f data/ref/chrM.fa -o results/${sample}.vcf results/${sample}.bam
    bgzip -f results/${sample}.vcf
    tabix -p vcf results/${sample}.vcf.gz
done

printf 'sample\tchrom\tpos\tref\talt\taf\n' > results/collapsed.tsv
for sample in "${SAMPLES[@]}"; do
    bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' results/${sample}.vcf.gz | awk -v s="${sample}" 'BEGIN{OFS="\t"}{print s,$0}' >> results/collapsed.tsv
done