#!/usr/bin/env bash
set -euo pipefail

mkdir -p results

samples=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

for sample in "${samples[@]}"; do
    [[ -f "results/${sample}.bam" ]] && continue

    bwa mem -t 4 data/ref/chrM.fa data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz > tmp.bam
    samtools view -b -@4 tmp.bam -o results/${sample}.bam
    samtools index results/${sample}.bam

    [[ ! -f "results/${sample}.vcf.gz" ]] && {
        bcftools view -Oz results/${sample}.bam > results/${sample}.vcf.gz
        bcftools index results/${sample}.vcf.gz
    }
done

if [[ ! -f "results/collapsed.tsv" ]]; then
    seqkit variant_aggregate -i results/*.vcf.gz -o results/collapsed.tsv -c sample chrom pos ref alt af -h
fi