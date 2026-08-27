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
for sample in $SAMPLES; do
    # Alignment
    if [ ! -f "results/${sample}.bam" ] || [ "data/raw/${sample}_1.fq.gz" -nt "results/${sample}.bam" ] || [ "data/raw/${sample}_2.fq.gz" -nt "results/${sample}.bam" ]; then
        bwa mem -t $THREADS data/ref/chrM.fa \
            -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
            data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz | samtools sort -@ $THREADS -o results/${sample}.bam
    fi

    # Index BAM
    if [ ! -f "results/${sample}.bam.ind" ] || [ "results/${sample}.bam" -nt "results/${sample}.bam.ind" ]; then
        samtools index -@ $THREADS results/${sample}.bam
    fi

    # Variant calling with lofreq (idempotent)
    if [ ! -f "results/${sample}.vcf.gz" ] || [ "results/${sample}.bam.ind" -nt "results/${sample}.vcf.gz" ]; then
        lofreq call-parallel --pp-threads $THREADS -f data/ref/chrM.fa -o results/${sample}.vcf results/${sample}.bam
    fi

    # Compress and index VCF
    if [ ! -f "results/${sample}.vcf.gz.tbi" ] || [ "results/${sample}.vcf" -nt "results/${sample}.vcf.gz" ]; then
        bgzip results/${sample}.vcf > results/${sample}.vcf.gz
        tabix -p vcf results/${sample}.vcf.gz
        rm results/${sample}.vcf
    fi

done

# Collapse step (idempotent)
if [ ! -f "results/collapsed.tsv" ] || [ "results/M117-bl.vcf.gz" -nt "results/collapsed.tsv" ] || [ "results/M117-ch.vcf.gz" -nt "results/collapsed.tsv" ] || [ "results/M117C1-bl.vcf.gz" -nt "results/collapsed.tsv" ] || [ "results/M117C1-ch.vcf.gz" -nt "results/collapsed.tsv" ]; then
    echo "sample\tchrom\tpos\tref\talt\taf" > results/collapsed.tsv
    for sample in $SAMPLES; do
        bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" results/${sample}.vcf.gz >> results/collapsed.tsv
    done
fi

exit 0