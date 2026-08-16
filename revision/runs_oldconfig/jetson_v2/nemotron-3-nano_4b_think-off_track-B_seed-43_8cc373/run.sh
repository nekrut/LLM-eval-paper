#!/usr/bin/env bash
set -euo pipefail

results=$(mktemp -d)
mkdir -p "$results"

for sample in M117-bl M117-ch M117C1-bl M117C1-ch; do
    bam="$results/${sample}.bam"
    bai="$results/${sample}.bam.bai"
    vcf="$results/${sample}.vcf.gz"

    if [[ ! -f "$bam" || ! -f "$bai" ]]; then
        bwa mem data/raw/${sample}_1.${sample//-/}/_2.${sample//-/}/_2.fq.gz \
            data/ref/chrM.fa "$bam"
        samtools view -ab $bam > "$bam"
        samtools index $bam $bai
    fi

    bcf="$results/${sample}.vcf.gz"
    if [[ ! -f "$bcf" ]]; then
        bcftools call -Oz -o "$bcf" "$bai"
    fi

    tabix -p vcf "$bcf"
done

echo "sample\tchrom\tpos\tref\talt\taf" > results/collapsed.tsv
for sample in M117-bl M117-ch M117C1-bl M117C1-ch; do
    vcf="$results/${sample}.vcf.gz"
    tabix -p vcf "$vcf"
    bcftools view -h $vcf | awk 'NR==1 {print "sample\tchrom\tpos\tref\talt\taf"}; NR>1 {split($0,a,"\t"); print a[0],a[1],a[2]+1,a[3],a[4]}' >> results/collapsed.tsv
done

rm -rf "$results"