#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES="M117-bl M117-ch M117C1-bl M117C1-ch"
RESULTS_DIR="results"

mkdir -p "$RESULTS_DIR"

# Reference indexing (idempotent)
if [ ! -f "data/ref/chrM.fa.ind" ] || [ "data/ref/chrM.fa.ind" -nt "data/ref/chrM.fa" ]; then
    samtools faidx data/ref/chrM.fa
    bwa index data/ref/chrM.fa
fi

# Per-sample processing
for SAMPLE in $SAMPLES; do
    # Alignment
    if [ ! -f "results/${SAMPLE}.bam" ] || [ "results/${SAMPLE}.bam" -nt "data/raw/${SAMPLE}_1.fq.gz data/raw/${SAMPLE}_2.fq.gz" ]; then
        bwa mem -t $THREADS data/ref/chrM.fa data/raw/${SAMPLE}_1.fq.gz data/raw/${SAMPLE}_2.fq.gz \
            -R "@RG\tID:${SAMPLE}\tSM:${SAMPLE}\tLB:${SAMPLE}\tPL:ILLUMINA"
        samtools sort -@ $THREADS -o results/${SAMPLE}.bam
    fi

    # Index BAM
    if [ ! -f "results/${SAMPLE}.bam.bai" ] || [ "results/${SAMPLE}.bam.bai" -nt "results/${SAMPLE}.bam" ]; then
        samtools index -@ $THREADS results/${SAMPLE}.bam
    fi

    # Variant calling with lofreq call-parallel
    if [ ! -f "results/${SAMPLE}.vcf.gz" ] || [ "results/${SAMPLE}.vcf.gz" -nt "results/${SAMPLE}.bam.bai" ]; then
        lofreq call-parallel --pp-threads $THREADS --verbose \
            --ref data/ref/chrM.fa --out results/${SAMPLE}.vcf \
            --sig --bonf \
            results/${SAMPLE}.bam
    fi

    # Compress and index VCF
    if [ ! -f "results/${SAMPLE}.vcf.gz" ] || [ "results/${SAMPLE}.vcf.gz" -nt "results/${SAMPLE}.vcf.gz.old" ]; then
        bgzip results/${SAMPLE}.vcf
        tabix -p vcf results/${SAMPLE}.vcf.gz
        rm results/${SAMPLE}.vcf
    fi

done

# Collapse step
if [ ! -f "results/collapsed.tsv" ] || [ "results/collapsed.tsv" -nt "results/*.vcf.gz" ]; then
    echo -e "sample\tchrom\tpos\tref\talt\taf" > results/collapsed.tsv
    for SAMPLE in $SAMPLES; do
        bcftools query -f "${SAMPLE}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" results/${SAMPLE}.vcf.gz >> results/collapsed.tsv
    done
fi

exit 0