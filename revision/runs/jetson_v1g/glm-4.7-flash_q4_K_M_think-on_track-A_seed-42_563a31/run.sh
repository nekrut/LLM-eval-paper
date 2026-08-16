#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES="M117-bl M117-ch M117C1-bl M117C1-ch"

mkdir -p results

# 2. Reference Indexing
if [ ! -f data/ref/chrM.fa.fai ] || [ ! -f data/ref/chrM.fa.bwt ]; then
    samtools faidx data/ref/chrM.fa
    bwa index data/ref/chrM.fa
fi

# 3, 4, 5. Alignment, Sort, Index
for SAMPLE in $SAMPLES; do
    if [ ! -f results/${SAMPLE}.bam ]; then
        bwa mem -t "$THREADS" -R "@RG\tID:${SAMPLE}\tSM:${SAMPLE}\tLB:${SAMPLE}\tPL:ILLUMINA" data/ref/chrM.fa data/raw/${SAMPLE}_1.fq.gz data/raw/${SAMPLE}_2.fq.gz | samtools sort -@ "$THREADS" -o results/${SAMPLE}.bam
    fi
    if [ ! -f results/${SAMPLE}.bam.bai ]; then
        samtools index -@ "$THREADS" results/${SAMPLE}.bam
    fi
done

# 6. Variant Calling
for SAMPLE in $SAMPLES; do
    if [ ! -f results/${SAMPLE}.vcf ]; then
        lofreq call-parallel --pp-threads "$THREADS" --verbose --ref data/ref/chrM.fa --out results/${SAMPLE}.vcf results/${SAMPLE}.bam
    fi
done

# 7. Compression & Indexing
for SAMPLE in $SAMPLES; do
    if [ ! -f results/${SAMPLE}.vcf.gz ]; then
        bgzip -c results/${SAMPLE}.vcf > results/${SAMPLE}.vcf.gz
        tabix -p vcf results/${SAMPLE}.vcf.gz
        rm results/${SAMPLE}.vcf
    fi
done

# 8. Collapsing
if [ ! -f results/collapsed.tsv ]; then
    HEADER="sample\tchrom\tpos\tref\talt\taf"
    printf '%s\n' "$HEADER" > results/collapsed.tsv
    for SAMPLE in $SAMPLES; do
        bcftools query -f '{sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' results/${SAMPLE}.vcf.gz >> results/collapsed.tsv
    done
fi