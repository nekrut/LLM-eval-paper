#!/usr/bin/env bash
set -euo pipefail

results=$(mktemp -d)
mkdir -p "$results"

for sample in M117-bl M117-ch M117C1-bl M117C1-ch; do
    bwa mem data/ref/chrM.fa data/raw/"$sample"_1.fq.gz data/raw/"$sample"_2.fq.gz -t 4 > "$results/${sample}.bam"
    samtools index "$results/${sample}.bam" -o "$results/${sample}.bam.bai"
    lofreq --input="$results/${sample}.bam" --output="$results/${sample}.vcf.gz" --threads=4
    tabix -p vcf "$results/${sample}.vcf.gz" -O "$results/${sample}.vcf.gz.tbi"
done

awk -F'\t' 'NR==1{print "sample\tchrom\tpos\tref\talt\taf"} NR>1{print $0}' results/*.vcf.gz > results/collapsed.tsv
rm -rf "$results"/* 2>/dev/null || true