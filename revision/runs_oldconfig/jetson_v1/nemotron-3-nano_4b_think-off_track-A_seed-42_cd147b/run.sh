#!/usr/bin/env bash
set -euo pipefail
THREADS=4
SAMPLES="M117-bl M117-ch M117C1-bl M117C1-ch"
RESULTS_DIR="results"

mkdir -p "$RESULTS_DIR"

# Reference indexing (idempotent)
if [ ! -f "data/ref/chrM.fa.ind" ] || [ data/ref/chrM.fa.ind -nt data/ref/chrM.fa ]; then
    samtools faidx data/ref/chrM.fa
    bwa index data/ref/chrM.fa
fi

for SAMPLE in $SAMPLES; do
    # Alignment (idempotent)
    if [ ! -f "results/${SAMPLE}.bam" ] || [ results/${SAMPLE}.bam -nt data/raw/${SAMPLE}_1.fq.gz data/raw/${SAMPLE}_2.fq.gz ]; then
        bwa mem -t $THREADS data/ref/chrM.fa \
            -R "@RG\tID:${SAMPLE}\tSM:${SAMPLE}\tLB:${SAMPLE}\tPL:ILLUMINA" \
            data/raw/${SAMPLE}_1.fq.gz data/raw/${SAMPLE}_2.fq.gz | samtools sort -@ $THREADS -o results/${SAMPLE}.bam
    fi

    # BAM indexing (idempotent)
    if [ ! -f "results/${SAMPLE}.bam.ind" ] || [ results/${SAMPLE}.bam.ind -nt results/${SAMPLE}.bam ]; then
        samtools index -@ $THREADS results/${SAMPLE}.bam
    fi

    # Variant calling (idempotent)
    if [ ! -f "results/${SAMPLE}.vcf.gz" ] || [ results/${SAMPLE}.vcf.gz.ind -nt results/${SAMPLE}.bam ]; then
        lofreq call-parallel --pp-threads $THREADS \
            --ref data/ref/chrM.fa \
            --input results/${SAMPLE}.bam \
            --output results/${SAMPLE}.vcf
    fi

    # Compression and indexing (idempotent)
    if [ ! -f "results/${SAMPLE}.vcf.gz" ] || [ results/${SAMPLE}.vcf.gz.ind -nt results/${SAMPLE}.vcf ]; then
        bgzip -c results/${SAMPLE}.vcf > results/${SAMPLE}.vcf.gz
        tabix -p vcf results/${SAMPLE}.vcf.gz
        rm results/${SAMPLE}.vcf
    fi

done

# Collapse step (idempotent)
if [ ! -f "results/collapsed.tsv" ] || [ results/collapsed.tsv -nt $(for S in $SAMPLES; do echo results/${S}.vcf.gz; done) ]; then
    HEADER="sample\tchrom\tpos\tref\talt\taf"
    echo "$HEADER"
    for S in $SAMPLES; do
        bcftools query -f '{SAMPLE}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' results/${S}.vcf.gz | tr '\n' ' '
    done | sed "s/^/$HEADER/" > results/collapsed.tsv
fi

exit 0