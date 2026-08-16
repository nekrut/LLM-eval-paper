#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES="M117-bl M117-ch M117C1-bl M117C1-ch"
RESULTS_DIR="results"

mkdir -p "$RESULTS_DIR"

# Reference indexing (idempotent)
if [ ! -f "data/ref/chrM.fa.ind" ] || [ "data/ref/chrM.fa.ind" -nt "data/ref/chrM.fa" ]; then
    samtools faidx data/ref/chrM.fa > /dev/null 2>&1
    bwa index data/ref/chrM.fa > /dev/null 2>&1
fi

# Per-sample processing
for sample in $SAMPLES; do
    # Alignment (idempotent)
    if [ ! -f "results/${sample}.bam" ] || [ "results/${sample}.bam" -nt "data/raw/${sample}_1. fq.gz" "data/raw/${sample}_2.fq.gz" ]; then
        bwa mem -t $THREADS data/ref/chrM.fa data/raw/${sample}_1. fq.gz data/raw/${sample}_2. fq.gz \
            -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" > "results/${sample}.bam"
    fi

    # BAM indexing (idempotent)
    if [ ! -f "results/${sample}.bam. bai" ] || [ "results/${sample}.bam. bai" -nt "results/${sample}.bam" ]; then
        samtools index -@ $THREADS results/${sample}.bam > /dev/null 2>&1
    fi

    # Variant calling (idempotent)
    if [ ! -f "results/${sample}.vcf.gz" ] || [ "results/${sample}.vcf.gz" -nt "results/${sample}.bam. bai" ]; then
        lofreq call-parallel --pp-threads $THREADS --verbose \
            --ref data/ref/chrM.fa --out results/${sample}.vcf \
            --sig --bonf results/${sample}.bam > /dev/null 2>&1
    fi

    # Compression and indexing (idempotent)
    if [ ! -f "results/${sample}.vcf.gz" ] || [ "results/${sample}.vcf.gz" -nt "results/${sample}.vcf" ]; then
        bgzip results/${sample}.vcf > /dev/null 2>&1
        tabix -p vcf results/${sample}.vcf.gz > /dev/null 2>&1
        rm results/${sample}.vcf
    fi

done

# Collapse step (idempotent)
if [ ! -f "results/collapsed.tsv" ] || [ "results/collapsed.tsv" -nt $(for f in results/*.vcf.gz; do echo "$f"; done) ]; then
    echo -e "sample\tchrom\tpos\tref\talt\taf" > results/collapsed.tsv
    for sample in $SAMPLES; do
        bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" results/${sample}.vcf.gz >> results/collapsed.tsv
    done
fi

exit 0