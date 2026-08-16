#!/usr/bin/env bash
set -euo pipefail

mkdir -p results

if [ ! -f data/ref/chrM.fa.bwt ]; then
    bwa index data/ref/chrM.fa
fi
if [ ! -f data/ref/chrM.fa.fai ]; then
    samtools faidx data/ref/chrM.fa
fi

SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

for sample in "${SAMPLES[@]}"; do
    if [ ! -f "results/${sample}.bam" ]; then
        bwa mem data/ref/chrM.fa \
            "data/raw/${sample}_1.fq.gz" \
            "data/raw/${sample}_2.fq.gz" | \
            samtools sort -o "results/${sample}.bam"
    fi

    if [ ! -f "results/${sample}.bam.bai" ]; then
        samtools index "results/${sample}.bam"
    fi

    if [ ! -f "results/${sample}.vcf.gz" ]; then
        lofreq call --bcf -f data/ref/chrM.fa \
            "results/${sample}.bam" | \
            bgzip > "results/${sample}.vcf.gz"
        tabix -p vcf "results/${sample}.vcf.gz"
    fi
done

if [ ! -f "results/collapsed.tsv" ]; then
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > results/collapsed.tsv

    for sample in "${SAMPLES[@]}"; do
        bcftools query -f '%CHROM\t%POS\t%REF\t%ALT[\t%AF]\n' \
            "results/${sample}.vcf.gz" | \
            awk -v s="${sample}" '{print s"\t"$0}' >> results/collapsed.tsv
    done
fi