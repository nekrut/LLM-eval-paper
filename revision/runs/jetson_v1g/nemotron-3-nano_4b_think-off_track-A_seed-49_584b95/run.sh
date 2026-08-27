#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES="M117-bl M117-ch M117C1-bl M117C1-ch"
RESULTS_DIR="results"

mkdir -p "$RESULTS_DIR"

# Reference indexing (idempotent)
if [[ ! -f "data/ref/chrM.fa.ind" ]] || [[ data/ref/chrM.fa.ind -nt data/ref/chrM.fa ]]; then
    samtools faidx data/ref/chrM.fa > /dev/null 2>&1
    bwa index data/ref/chrM.fa > /dev/null 2>&1
fi

# Per-sample processing
for SAMPLE in $SAMPLES; do
    # Alignment
    if [[ ! -f "results/${SAMPLE}.bam" ]] || [[ results/${SAMPLE}.bam -nt data/raw/${SAMPLE}_1.${SAMPLE//-/_2}.fq.gz ]]; then
        bwa mem -t $THREADS -R "@RG\tID:${SAMPLE}\tSM:${SAMPLE}\tLB:${SAMPLE}\tPL:ILLUMINA" \
            data/raw/${SAMPLE}_1.${SAMPLE//-/_2}.fq.gz data/raw/${SAMPLE}_2.${SAMPLE//-/_2}.fq.gz | samtools sort -@ $THREADS -o results/${SAMPLE}.bam > /dev/null 2>&1
    fi

    # Index BAM
    if [[ ! -f "results/${SAMPLE}.bam.bai" ]] || [[ results/${SAMPLE}.bam.bai -nt results/${SAMPLE}.bam ]]; then
        samtools index -@ $THREADS results/${SAMPLE}.bam > /dev/null 2>&1
    fi

    # Variant calling with lofreq call-parallel (idempotent)
    if [[ ! -f "results/${SAMPLE}.vcf.gz" ]] || [[ results/${SAMPLE}.vcf.gz.${SAMPLE//./_} -nt results/${SAMPLE}.bam ]]; then
        lofreq call-parallel --pp-threads $THREADS --verbose \
            --ref data/ref/chrM.fa --out results/${SAMPLE}.vcf \
            --sig --bonf results/${SAMPLE}.bam > /dev/null 2>&1
    fi

    # Compress and index VCF (idempotent)
    if [[ ! -f "results/${SAMPLE}.vcf.gz" ]] || [[ results/${SAMPLE}.vcf.gz.${SAMPLE//./_} -nt results/${SAMPLE}.vcf ]]; then
        bgzip results/${SAMPLE}.vcf > /dev/null 2>&1
        tabix -p vcf results/${SAMPLE}.vcf.gz > /dev/null 2>&1
        rm -f results/${SAMPLE}.vcf
    fi

done

# Collapse step (idempotent)
if [[ ! -f "results/collapsed.tsv" ]] || [[ results/collapsed.tsv -nt $(for S in $SAMPLES; do echo results/${S}.vcf.gz; done) ]]; then
    HEADER="sample\tchrom\tpos\tref\talt\taf"
    echo "$HEADER" > results/collapsed.tsv
    for S in $SAMPLES; do
        bcftools query -f '{SAMPLE}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' results/${S}.vcf.gz >> results/collapsed.tsv
    done
fi

exit 0