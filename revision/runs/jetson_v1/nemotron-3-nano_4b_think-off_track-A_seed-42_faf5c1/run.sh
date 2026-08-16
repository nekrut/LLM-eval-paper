#!/usr/bin/env bash
set -euo pipefail
THREADS=4
SAMPLES="M117-bl M117-ch M117C1-bl M117C1-ch"
mkdir -p results

# Reference indexing (once)
if [ ! -f data/ref/chrM.fa.ind ] || [ ! -s data/ref/chrM.ffai ]; then
    samtools faidx data/ref/chrM.fa > /dev/null 2>&1
    bwa index data/ref/chrM.fa > /dev/null 2>&1
fi

# Per-sample processing
for sample in $SAMPLES; do
    # Alignment
    if [ ! -f results/${sample}.bam ] || [ $(stat -c %Y results/${sample}.bam) -lt $(stat -c %y data/raw/${sample}_1.fq.gz 2>/dev/null || stat -c %y data/raw/${sample}_2.fq.gz 2>/dev/null) ]; then
        bwa mem -t $THREADS -R "RG\@${sample}\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
            data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz | samtools sort -@ $THREADS -o results/${sample}.bam > /dev/null 2>&1
    fi

    # Index BAM
    if [ ! -f results/${sample}.bam.ind ] || [ $(stat -c %Y results/${sample}.bam.ind) -lt $(stat -c %y results/${sample}.bam) ]; then
        samtools index -@ $THREADS results/${sample}.bam > /dev/null 2>&1
    fi

    # Variant calling
    if [ ! -f results/${sample}.vcf.gz ] || [ $(stat -c %Y results/${sample}.vcf.gz) -lt $(stat -c %y data/ref/chrM.ffai) ]; then
        lofreq call-parallel --pp-threads $THREADS \
            -R "RG\@${sample}\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
            results/${sample}.bam data/ref/chrM.fa > results/${sample}.vcf 2>/dev/null
        bgzip -c results/${sample}.vcf > results/${sample}.vcf.gz
        tabix -p vcf results/${sample}.vcf.gz > results/${sample}.vcf.gz.tbi
        rm -f results/${sample}.vcf
    fi

done

# Collapse TSV
if [ ! -f results/collapsed.tsv ] || [ $(stat -c %y results/collapsed.tsv) -lt $(stat -c %y data/ref/chrM.ffai) ]; then
    echo "sample\tchrom\tpos\tref\talt\taf" > results/collapsed.tsv
    for sample in $SAMPLES; do
        bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" \
            results/${sample}.vcf.gz >> results/collapsed.tsv
    done
fi

exit 0