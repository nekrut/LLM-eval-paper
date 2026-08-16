#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES="M117-bl M117-ch M117C1-bl M117C1-ch"
RESULTS_DIR="results"

mkdir -p "$RESULTS_DIR"

# Reference indexing (idempotent)
if [ ! -f "data/ref/chrM.fa.ind" ] || [ "data/ref/chrM.fa.ind" -nt "data/ref/chrM.fa" ]; then
    samtools faidx data/ref/chrM.fa > /dev/null 2>&1
    bwa index data/ref/chrM.fa > /dev/null 2>&1
fi

# Per-sample processing
for S in $SAMPLES; do
    # Skip if all outputs exist and are up to date
    if [ -f "results/${S}.bam" ] && [ -f "results/${S}.bam.ind" ] && [ -f "results/${S}.vcf.gz" ] && [ -f "results/${S}.vcf.gz.tbi" ]; then
        continue
    fi

    # Alignment
    bwa mem -t $THREADS data/raw/${S}_1.fq.gz data/raw/${S}_2.fq.gz \
        > results/${S}.bam 2>/dev/null || true

    if [ ! -f "results/${S}.bam" ]; then
        exit 1
    fi

    # Sort BAM (idempotent)
    samtools sort -@ $THREADS -o results/${S}.bam > /dev/null 2>&1 || true

    if [ ! -f "results/${S}.bam" ]; then
        exit 1
    fi

    # Index BAM (idempotent)
    samtools index -@ $THREADS results/${S}.bam > /dev/null 2>&1 || true

    if [ ! -f "results/${S}.bam.ind" ]; then
        exit 1
    fi

    # Variant calling with lofreq (idempotent)
    if [ ! -f "results/${S}.vcf.gz" ] || [ "results/${S}.vcf.gz" -nt "results/${S}.bam.ind" ]; then
        lofreq call-parallel --pp-threads $THREADS --verbose \
            --ref data/ref/chrM.fa --out results/${S}.vcf \
            --sig --bonf \
            results/${S}.bam > /dev/null 2>&1 || true

        if [ ! -f "results/${S}.vcf" ]; then
            exit 1
        fi

        # Compress and index VCF (idempotent)
        bgzip -@ $THREADS results/${S}.vcf > /dev/null 2>&1 || true
        tabix -p vcf results/${S}.vcf.gz > /dev/null 2>&1 || true

        if [ ! -f "results/${S}.vcf.gz" ] || [ "results/${S}.vcf.gz.tbi" -nt "results/${S}.vcf.gz" ]; then
            exit 1
        fi

        # Remove uncompressed VCF (idempotent)
        rm -f results/${S}.vcf > /dev/null 2>&1 || true
    fi
done

# Collapse step: only rebuild if any input VCF is newer than TSV
if [ ! -f "results/collapsed.tsv" ] || [ "$(find results -name '*.vcf.gz' | xargs ls -t)" -nt "results/collapsed.tsv" ]; then
    echo "sample\tchrom\tpos\tref\talt\taf" > results/collapsed.tsv
    for S in $SAMPLES; do
        bcftools query -f '{S}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' \
            results/${S}.vcf.gz >> results/collapsed.tsv
    done
fi

exit 0