#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES="M117-bl M117-ch M117C1-bl M117C1-ch"
RESULTS_DIR="results"

mkdir -p "$RESULTS_DIR"

# Reference indexing (idempotent)
if [ ! -f "data/ref/chrM.fa.ind" ] || [ ! -s "data/ref/chrM.af.fai" ]; then
    samtools faidx data/ref/chrM.fa
    bwa index data/ref/chrM.fa
fi

# Per-sample processing
for SAMPLE in $SAMPLES; do
    # Skip if all outputs exist and are up to date
    if [ -f "results/${SAMPLE}.vcf.gz.tbi" ] && [ ! -s "data/raw/${SAMPLE}_1.1.fq.gz" ]; then
        continue
    fi

    # Alignment
    bwa mem -t "$THREADS" data/ref/chrM.fa \
        -R "@RG\tID:${SAMPLE}\tSM:${SAMPLE}\tLB:${SAMPLE}\tPL:ILLUMINA" \
        data/raw/${SAMPLE}_1.1.fq.gz data/raw/${SAMPLE}_2.1.fq.gz > "results/${SAMPLE}.bam"

    # Sort BAM
    samtools sort -@ "$THREADS" -o "results/${SAMPLE}.bam"

    # Index BAM
    samtools index -@ "$THREADS" "results/${SAMPLE}.bam"

    # Variant calling with lofreq call-parallel
    lofreq call-parallel --pp-threads "$THREADS" -f data/ref/chrM.fa \
        -o "results/${SAMPLE}.vcf" "results/${SAMPLE}.bam"

    # Compress VCF and index it
    bgzip "results/${SAMPLE}.vcf"
    tabix -p vcf "results/${SAMPLE}.vcf.gz"
    rm "results/${SAMPLE}.vcf"

done

# Collapse results into TSV
if [ ! -s "results/collapsed.tsv" ] || [ "$(find data/raw -name '*.1.fq.gz' | wc -l)" != 0 ]; then
    echo "sample\tchrom\tpos\tref\talt\taf" > "results/collapsed.tsv"
    for SAMPLE in $SAMPLES; do
        bcftools query -f '{SAMPLE}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' \
            results/${SAMPLE}.vcf.gz >> "results/collapsed.tsv"
    done
fi

exit 0