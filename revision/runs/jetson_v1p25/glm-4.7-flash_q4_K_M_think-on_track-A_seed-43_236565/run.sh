#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

mkdir -p results

# Reference indexing
if [ ! -f data/ref/chrM.fa.fai ]; then
    samtools faidx data/ref/chrM.fa
fi
if [ ! -f data/ref/chrM.fa.bwt ]; then
    bwa index data/ref/chrM.fa
fi

# Per-sample processing
for SAMPLE in "${SAMPLES[@]}"; do
    # Alignment
    if [ ! -f results/${SAMPLE}.bam ]; then
        bwa mem -t $THREADS -R "@RG\tID:${SAMPLE}\tSM:${SAMPLE}\tLB:${SAMPLE}\tPL:ILLUMINA" data/ref/chrM.fa data/raw/${SAMPLE}_1.fq.gz data/raw/${SAMPLE}_2.fq.gz | samtools sort -@ $THREADS -o results/${SAMPLE}.bam
    fi

    # BAM Index
    if [ ! -f results/${SAMPLE}.bam.bai ]; then
        samtools index -@ $THREADS results/${SAMPLE}.bam
    fi

    # Variant Calling
    if [ ! -f results/${SAMPLE}.vcf ]; then
        lofreq call-parallel --pp-threads $THREADS -f data/ref/chrM.fa -o results/${SAMPLE}.vcf results/${SAMPLE}.bam
    fi

    # VCF Compression
    if [ ! -f results/${SAMPLE}.vcf.gz ]; then
        bgzip -c results/${SAMPLE}.vcf > results/${SAMPLE}.vcf.gz
    fi

    # VCF Index
    if [ ! -f results/${SAMPLE}.vcf.gz.tbi ]; then
        tabix -p vcf results/${SAMPLE}.vcf.gz
    fi

    # Cleanup intermediate
    rm results/${SAMPLE}.vcf
done

# Collapsing
# Check if TSV exists and is up to date
TSV_TIME=0
if [ -f results/collapsed.tsv ]; then
    TSV_TIME=$(stat -c %Y results/collapsed.tsv)
fi
NEED_REBUILD=0
for SAMPLE in "${SAMPLES[@]}"; do
    VCF_TIME=$(stat -c %Y results/${SAMPLE}.vcf.gz)
    if [ $VCF_TIME -gt $TSV_TIME ]; then
        NEED_REBUILD=1
        break
    fi
done

if [ $NEED_REBUILD -eq 1 ]; then
    printf "sample\tchrom\tpos\tref\talt\taf\n" > results/collapsed.tsv
    for SAMPLE in "${SAMPLES[@]}"; do
        bcftools query -f '%SAMPLE\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' results/${SAMPLE}.vcf.gz >> results/collapsed.tsv
    done
fi