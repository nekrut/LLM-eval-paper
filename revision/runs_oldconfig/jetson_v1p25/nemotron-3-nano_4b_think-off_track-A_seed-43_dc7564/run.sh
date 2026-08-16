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
    # Skip if all outputs exist and are up to date
    if [ -f "results/${sample}.bam" ] && [ -f "results/${sample}.bam.ind" ] && \
       [ -f "results/${sample}.vcf.gz" ] && [ -f "results/${sample}.vcf.gz.tbi" ]; then
        continue
    fi

    # Alignment
    bwa mem -t $THREADS data/raw/"$sample"_1. fq.gz data/raw/"$sample"_2.fq.gz \
        -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" > "results/${sample}.bam"

    # Sort BAM
    samtools sort -@ $THREADS -o "results/${sample}.bam" "results/${sample}.bam.tmp"
    mv "results/${sample}.bam.tmp" "results/${sample}.bam"

    # Index BAM
    samtools index -@ $THREADS "results/${sample}.bam"

    # Variant calling with lofreq call-parallel
    lofreq call-parallel --pp-threads 4 -f data/ref/chrM.fa -o results/"$sample".vcf results/"$sample".bam

    # Compress and index VCF
    bgzip "results/${sample}.vcf"
    tabix -p vcf "results/${sample}.vcf.gz"
    rm "results/${sample}.vcf"

done

# Collapse step
if [ ! -f "results/collapsed.tsv" ] || \
   ( [ -n "$(find results -name '*.vcf.gz' | xargs -I{} bcftools query -f '{sample}\t%CHROM\tt%POS\tref\talt\tinfo/af\n' {} )" ] && \
     ! [ -s "results/collapsed.tsv" ]; then
    echo "sample\tchrom\tpos\tref\talt\taf"
    for sample in $SAMPLES; do
        bcftools query -f '{sample}\t%CHROM\tt%POS\tref\talt\tinfo/af\n' results/"$sample".vcf.gz >> "results/collapsed.tsv"
    done
fi

exit 0