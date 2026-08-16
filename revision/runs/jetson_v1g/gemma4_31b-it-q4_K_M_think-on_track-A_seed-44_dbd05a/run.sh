#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
mkdir -p results

if [ ! -f data/ref/chrM.fa.fai ]; then
    samtools faidx data/ref/chrM.fa
fi

if [ ! -f data/ref/chrM.fa.bwt ]; then
    bwa index data/ref/chrM.fa
fi

for sample in "${SAMPLES[@]}"; do
    if [ ! -f results/${sample}.bam ]; then
        bwa mem -t ${THREADS} -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
            data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz | \
            samtools sort -@ ${THREADS} -o results/${sample}.bam
    fi

    if [ ! -f results/${sample}.bam.bai ]; then
        samtools index -@ ${THREADS} results/${sample}.bam
    fi

    if [ ! -f results/${sample}.vcf.gz.tbi ]; then
        lofreq call-parallel --pp-threads ${THREADS} --verbose \
            --ref data/ref/chrM.fa --out results/${sample}.vcf \
            results/${sample}.bam
        bgzip -c results/${sample}.vcf > results/${sample}.vcf.gz
        tabix -p vcf results/${sample}.vcf.gz
        rm -f results/${sample}.vcf
    fi
done

REBUILD=false
if [ ! -f results/collapsed.tsv ]; then
    REBUILD=true
else
    for sample in "${SAMPLES[@]}"; do
        if [ results/${sample}.vcf.gz -nt results/collapsed.tsv ]; then
            REBUILD=true
            break
        fi
    done
fi

if [ "$REBUILD" = true ]; then
    printf "sample\tchrom\tpos\tref\talt\taf\n" > results/collapsed.tsv
    for sample in "${SAMPLES[@]}"; do
        bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" results/${sample}.vcf.gz >> results/collapsed.tsv
    done
fi