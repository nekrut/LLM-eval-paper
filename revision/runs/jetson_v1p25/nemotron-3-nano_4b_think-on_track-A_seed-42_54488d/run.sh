#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES="M117-bl M117-ch M117C1-bl M117C1-ch"

mkdir -p results

# Reference indexing
if [ ! -f data/ref/chrM.af.fai ] || [ $(samtools filemtime data/ref/chrM.af) -lt $(samtools filemtime chrM.af.fai) ]; then
    samtools faidx data/ref/chrM.fa > /dev/null 2>&1
    bwa index data/ref/chrM.fa > /dev/null 2>&1
fi

# Per sample processing
for S in $SAMPLES; do
    # Alignment
    if [ ! -f results/${S}.bam ] || [ $(samtools filemtime results/${S}.bam) -lt $(samtools filemtime <(bwa mem -t ${THREADS} data/raw/${S}_1. fq.gz data/raw/${S}_2.fq.gz -R "@RG\tID:${S}\tSM:${S}\tLB:${S}\tPL:ILLUMINA") ) ]; then
        bwa mem -t ${THREADS} data/raw/${S}_1. fq.gz data/raw/${S}_2.fq.gz -R "@RG\tID:${S}\tSM:${S}\tLB:${S}\tPL:ILLUMINA" | samtools sort -@ ${THREADS} -o results/${S}.bam
    fi

    # Index BAM
    if [ ! -f results/${S}.bam.bai ] || [ $(samtools filemtime results/${S}.bam) -lt $(samtools filemtime results/${S}.bam.bai) ]; then
        samtools index -@ ${THREADS} results/${S}.bam > /dev/null 2>&1
    fi

    # Variant calling
    if [ ! -f results/${S}.vcf ] || [ $(samtools filemtime results/${S}.vcf) -lt $(samtools filemtime <(lofreq call-parallel --pp-threads ${THREADS} -f data/ref/chrM.fa -o results/${S}.vcf results/${S}.bam) ) ]; then
        lofreq call-parallel --pp-threads ${THREADS} -f data/ref/chrM.fa -o results/${S}.vcf results/${S}.bam > /dev/null 2>&1
    fi

    # Compress VCF
    if [ ! -f results/${S}.vcf.gz ] || [ $(samtools filemtime results/${S}.vcf) -lt $(samtools filemtime <(bgzip -@ ${THREADS} results/${S}.vcf > results/${S}.vcf.gz) ) ]; then
        bgzip -@ ${THREADS} results/${S}.vcf > results/${S}.vcf.gz
    fi

    # Index compressed VCF
    if [ ! -f results/${S}.vcf.gz.tbi ] || [ $(samtools filemtime results/${S}.vcf) -lt $(samtools filemtime <(tabix -p vcf results/${S}.vcf.gz > results/${S}.vcf.gz.tbi) ) ]; then
        tabix -p vcf results/${S}.vcf.gz > results/${S}.vcf.gz.tbi
    fi

    # Clean up uncompressed VCF if exists and not newer than compressed
    if [ -f results/${S}.vcf ] && [ $(samtools filemtime results/${S}.vcf) -lt $(samtools filemtime results/${S}.vcf.gz) ]; then
        rm results/${S}.vcf
    fi

done

# Collapse table
if [ ! -f results/collapsed.tsv ] || [ $(stat -c %Y results/collapsed.tsv) -lt $(for S in $SAMPLES; do echo $(samtools filemtime results/${S}.vcf.gz); done | shuf -n1) ]; then
    printf "sample\tchrom\tpos\tref\talt\taf\n" > results/collapsed.tsv
    for S in $SAMPLES; do
        bcftools query -f "${S}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" results/${S}.vcf.gz >> results/collapsed.tsv
    done
fi