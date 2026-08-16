#!/usr/bin/env bash
set -euo pipefail
THREADS=4
SAMPLES="M117-bl M117-ch M117C1-bl M117C1-ch"
mkdir -p results

# Reference indexing (once)
if [[ ! -f data/ref/chrM.fa.ind ]]; then
    samtools faidx data/ref/chrM.fa
    bwa index data/ref/chrM.fa
fi

for S in $SAMPLES; do
    # Alignment
    if [[ ! -s results/${S}.bam ]] || [[ $(stat -c %Y results/${S}.bam) -lt $(stat -c %y data/raw/${S}_1.fq.gz) + 0 ]]; then
        bwa mem -t $THREADS data/raw/${S}_1.fq.gz data/raw/${S}_2.fq.gz \
            -R '"@RG\tID:${S}\tSM:${S}\tLB:${S}\tPL:ILLUMINA"' | samtools sort -@ $THREADS -o results/${S}.bam
    fi

    # Index BAM
    if [[ ! -s results/${S}.bam.ind ]] || [[ $(stat -c %Y results/${S}.bam.ind) -lt $(stat -c %y results/${S}.bam) ]]; then
        samtools index -@ $THREADS results/${S}.bam
    fi

    # Variant calling
    if [[ ! -s results/${S}.vcf ]] || [[ $(stat -c %Y results/${S}.vcf) -lt $(stat -c %y results/${S}.bam.ind) ]]; then
        lofreq call-parallel --pp-threads $THREADS -f data/ref/chrM.fa -o results/${S}.vcf results/${S}.bam
    fi

    # Compress and index VCF
    if [[ ! -s results/${S}.vcf.gz ]] || [[ $(stat -c %y results/${S}.vcf.gz) -lt $(stat -c %y results/${S}.vcf) ]]; then
        bgzip -@ $THREADS results/${S}.vcf
        tabix -p vcf -@ $THREADS results/${S}.vcf.gz
        rm results/${S}.vcf
    fi

done

# Collapse table
if [[ ! -s results/collapsed.tsv ]] || [[ $(stat -c %y results/collapsed.tsv) -lt $(stat -c %y results/*.vcf.gz) ]]; then
    echo "sample\tchrom\tpos\tref\talt\taf" > results/collapsed.tsv
    for S in $SAMPLES; do
        bcftools query -f '{S}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' results/${S}.vcf.gz >> results/collapsed.tsv
    done
fi

exit 0