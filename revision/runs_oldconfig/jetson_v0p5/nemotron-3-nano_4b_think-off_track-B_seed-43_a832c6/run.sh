#!/usr/bin/env bash
set -euo pipefail

results=$(mktemp -d)
mkdir -p "$results"

for sample in M117-bl M117-ch M117C1-bl M117C1-ch; do
    bwa mem data/ref/chrM.fa data/raw/"$sample"_1.*.fq.gz data/raw/"$sample"_2.*.fq.gz -t 4 > "$results/${sample}.bam"
    samtools index "$results/${sample}.bam" -o "$results/${sample}.bam.bai"

    lofreq --input="$results/${sample}.bam" --output="$results/${sample}_lofreq.txt" --threads=4
    bcftools view -Oz "$results/${sample}.bam" > "$results/${sample}.vcf.gz"
    tabix -p vcf "$results/${sample}.vcf.gz"

    awk 'NR==1 {print "sample\tchrom\tpos\tref\talt\taf"} NR>1 {split($0,a,"\t"); print a[0],a[2],a[3],a[4],a[5]}' "$results/${sample}_lofreq.txt" >> "$results/collapsed.tsv"
done

rm -rf "$results"/*.bam "$results"/*.bai "$results"/*.vcf.gz "$results"/*.tbi
mv "$results"/*.txt "$results"/
mv "$results"/collapsed.tsv "$results"/
rmdir "$results"