#!/usr/bin/env bash
set -euo pipefail

if [ -s results/collapsed.tsv ]; then
    exit 0
fi

mkdir -p results

samples=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

for sample in "${samples[@]}"; do
    if [ -f results/${sample}.bam ]; then
        continue
    fi

    fq1=data/raw/${sample}_1.fq.gz
    fq2=data/raw/${sample}_2.fq.gz

    bwa mem data/ref/chrM.fa "$fq1" "$fq2" |
        samtools view -b - |
        samtools sort -o results/${sample}.bam -

    samtools index results/${sample}.bam

    lofreq call --ref data/ref/chrM.fa -o results/${sample}.vcf.gz results/${sample}.bam

    tabix -p vcf results/${sample}.vcf.gz
done

{
    printf "sample\tchrom\tpos\tref\talt\taf\n"
    for sample in "${samples[@]}"; do
        bcftools query -f $'%CHROM\t%POS\t%REF\t%ALT\t%AF\n' results/${sample}.vcf.gz |
            awk -v s="${sample}" '{print s"\t"$0}'
    done
} > results/collapsed.tsv