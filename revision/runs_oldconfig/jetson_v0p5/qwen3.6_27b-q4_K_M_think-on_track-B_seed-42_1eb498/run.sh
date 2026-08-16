#!/usr/bin/env bash
set -euo pipefail

THREADS=${THREADS:-4}

mkdir -p results

if [ ! -f data/ref/chrM.fa.bwt ]; then
    bwa index data/ref/chrM.fa
fi
if [ ! -f data/ref/chrM.fa.fai ]; then
    samtools faidx data/ref/chrM.fa
fi

for sample in M117-bl M117-ch M117C1-bl M117C1-ch; do
    if [ ! -f "results/${sample}.bam" ]; then
        bwa mem -t "${THREADS}" data/ref/chrM.fa \
            "data/raw/${sample}_1.fq.gz" \
            "data/raw/${sample}_2.fq.gz" | \
            samtools sort -@ "${THREADS}" -o "results/${sample}.bam"
    fi

    if [ ! -f "results/${sample}.bam.bai" ]; then
        samtools index "results/${sample}.bam"
    fi

    if [ ! -f "results/${sample}.vcf.gz" ]; then
        lofreq call --bams "results/${sample}.bam" \
            -f data/ref/chrM.fa | \
            bcftools view -Oz -o "results/${sample}.vcf.gz"
    fi

    if [ ! -f "results/${sample}.vcf.gz.tbi" ]; then
        tabix -p vcf "results/${sample}.vcf.gz"
    fi
done

{
    printf 'sample\tchrom\tpos\tref\talt\taf\n'
    for sample in M117-bl M117-ch M117C1-bl M117C1-ch; do
        bcftools query -H -f '%CHROM\t%POS\t%REF\t[%ALT\t%INFO/AF]\n' \
            "results/${sample}.vcf.gz" | \
        awk -v s="${sample}" '{print s"\t"$0}'
    done
} > results/collapsed.tsv