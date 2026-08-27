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

# Per-sample processing
for S in $SAMPLES; do
    # Alignment
    if [ ! -f "results/${S}.bam" ] || [ results/${S}.bam -nt data/raw/${S}_1.fq.gz,data/raw/${S}_2.fq.gz ]; then
        bwa mem -t $THREADS -R "@RG\tID:${S}\tSM:${S}\tLB:${S}\tPL:ILLUMINA" \
            data/raw/${S}_1.fq.gz data/raw/${S}_2.fq.gz | samtools sort -@ $THREADS -o results/${S}.bam
    fi

    # BAM indexing
    if [ ! -f "results/${S}.bam.ind" ] || [ results/${S}.bam.ind -nt results/${S}.bam ]; then
        samtools index -@ $THREADS results/${S}.bam
    fi

    # Variant calling
    if [ ! -f "results/${S}.vcf.gz" ] || [ results/${S}.vcf.gz -nt data/ref/chrM.fa,results/${S}.bam ]; then
        lofreq call-parallel --pp-threads $THREADS -f data/ref/chrM.fa -o results/${S}.vcf results/${S}.bam
    fi

    # Compression and indexing
    if [ ! -f "results/${S}.vcf.gz" ] || [ results/${S}.vcf.gz -nt results/${S}.vcf ]; then
        bgzip -c results/${S}.vcf > results/${S}.vcf.gz
        tabix -p vcf results/${S}.vcf.gz
        rm results/${S}.vcf
    fi

    # Idempotency: skip if VCF already compressed and indexed
    if [ ! -f "results/${S}.vcf.ind" ] || [ results/${S}.vcf.ind -nt results/${S}.vcf.gz ]; then
        tabix -p vcf results/${S}.vcf.gz
    fi

done

# Collapse step
if [ ! -f "results/collapsed.tsv" ] || [ results/collapsed.tsv -nt $(for S in $SAMPLES; do echo results/${S}.vcf.gz; done) ]; then
    HEADER="sample\tchrom\tpos\tref\talt\taf"
    echo "$HEADER"
    for S in $SAMPLES; do
        bcftools query -f '{S}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' results/${S}.vcf.gz | tr '\n' ' '
    done | sed "s/^/$HEADER/" > results/collapsed.tsv
fi

exit 0