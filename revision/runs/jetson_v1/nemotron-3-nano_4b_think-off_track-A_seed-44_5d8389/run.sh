#!/usr/bin/env bash
set -euo pipefail
THREADS=4
SAMPLES="M117-bl M117-ch M117C1-bl M117C1-ch"
RESULTS_DIR="results"

mkdir -p "$RESULTS_DIR"

# Reference indexing (once)
if [ ! -f "data/ref/chrM.fa.ind" ] || [ data/ref/chrM.fa.ind -nt data/ref/chrM.fa ]; then
    samtools faidx data/ref/chrM.fa > /dev/null 2>&1
    bwa index data/ref/chrM.fa > /dev/null 2>&1
fi

# Per-sample processing
for sample in $SAMPLES; do
    # BWA alignment
    if [ ! -f "results/${sample}.bam" ] || [ results/${sample}.bam -nt data/raw/${sample}_1.1.fq.gz data/raw/${sample}_2.1.fq.gz ]; then
        bwa mem -t $THREADS data/ref/chrM.fa \
            -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
            data/raw/${sample}_1.1.fq.gz data/raw/${sample}_2.1.fq.gz | samtools sort -@ $THREADS -o results/${sample}.bam > /dev/null 2>&1
    fi

    # BAM indexing
    if [ ! -f "results/${sample}.bam.bai" ] || [ results/${sample}.bam.bai -nt results/${sample}.bam ]; then
        samtools index -@ $THREADS results/${sample}.bam > /dev/null 2>&1
    fi

    # Variant calling with lofreq call-parallel
    if [ ! -f "results/${sample}.vcf.gz" ] || [ results/${sample}.vcf.gz -nt results/${sample}.bam.bai ]; then
        lofreq call-parallel --pp-threads $THREADS \
            --ref data/ref/chrM.fa \
            --input results/${sample}.bam \
            --output results/${sample}.vcf > /dev/null 2>&1
    fi

    # Compress VCF and index
    if [ ! -f "results/${sample}.vcf.gz.tbi" ] || [ results/${sample}.vcf.gz.tbi -nt results/${sample}.vcf ]; then
        bgzip -c results/${sample}.vcf > results/${sample}.vcf.gz
        tabix -p vcf results/${sample}.vcf.gz > results/${sample}.vcf.gz.tbi
        rm results/${sample}.vcf
    fi

done

# Collapse step
if [ ! -f "results/collapsed.tsv" ] || [ results/collapsed.tsv -nt $(for s in $SAMPLES; do echo results/${s}.vcf.gz; done) ]; then
    echo "sample\tchrom\tpos\tref\talt\taf" > results/collapsed.tsv
    for sample in $SAMPLES; do
        bcftools query -f '{sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' results/${sample}.vcf.gz >> results/collapsed.tsv
    done
fi

exit 0