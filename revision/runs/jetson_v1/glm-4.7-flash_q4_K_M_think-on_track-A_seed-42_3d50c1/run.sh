#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES="M117-bl M117-ch M117C1-bl M117C1-ch"

mkdir -p results

# 2. Reference indexing (once)
if [ ! -f data/ref/chrM.fa.fai ]; then
    samtools faidx data/ref/chrM.fa
fi
if [ ! -f data/ref/chrM.fa.bwt ]; then
    bwa index data/ref/chrM.fa
fi

# 3, 4, 5. Alignment, Sort, Index
for sample in $SAMPLES; do
    # Alignment and Sort
    if [ ! -f results/${sample}.bam ]; then
        bwa mem -t ${THREADS} -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" data/ref/chrM.fa data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz | samtools sort -@ ${THREADS} -o results/${sample}.bam
    fi

    # BAM Index
    if [ ! -f results/${sample}.bam.bai ]; then
        samtools index -@ ${THREADS} results/${sample}.bam
    fi

    # 6. Variant calling
    if [ ! -f results/${sample}.vcf ]; then
        lofreq call-parallel --pp-threads ${THREADS} -f data/ref/chrM.fa results/${sample}.bam -o results/${sample}.vcf
    fi

    # 7. Compression and Indexing
    if [ ! -f results/${sample}.vcf.gz ]; then
        bgzip -c results/${sample}.vcf > results/${sample}.vcf.gz
        tabix -p vcf results/${sample}.vcf.gz
        rm results/${sample}.vcf
    fi
done

# 8. Collapse
if [ ! -f results/collapsed.tsv ]; then
    echo -e "sample\tchrom\tpos\tref\talt\taf" > results/collapsed.tsv
    for sample in $SAMPLES; do
        bcftools query -f '{sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' results/${sample}.vcf.gz >> results/collapsed.tsv
    done
fi