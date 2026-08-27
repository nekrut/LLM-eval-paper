#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES="M117-bl M117-ch M117C1-bl M117C1-ch"
RESULTS_DIR="results"

mkdir -p "$RESULTS_DIR"

# Reference indexing (idempotent)
if [ ! -f "data/ref/chrM.fa.ind" ] || [ ! -s "data/ref/chrM.af.fai" ]; then
    samtools faidx data/ref/chrM.fa > /dev/null 2>&1
    bwa index data/ref/chrM.fa > /dev/null 2>&1
fi

# Per-sample processing
for sample in $SAMPLES; do
    # Skip if all outputs exist and are up to date
    if [ -f "results/${sample}.vcf.gz" ] && [ -f "results/${sample}.bam" ] && \
       [ ! -s "results/${sample}.vcf.gz.tbi" ] || [ ! -s "results/${sample}.bam.bai" ]; then
        continue
    fi

    # Alignment
    bwa mem -t $THREADS data/raw/"$sample"_1.fq.gz data/raw/"$sample"_2.fq.gz \
        > results/"${sample}".bam 2>/dev/null || exit 1

    # Sort BAM
    samtools sort -@ $THREADS -o results/"${sample}".bam 2>/dev/null || exit 1

    # Index BAM
    samtools index -@ $THREADS results/"${sample}".bam 2>/dev/null || exit 1

    # Variant calling
    lofreq call-parallel --pp-threads $THREADS -f data/ref/chrM.fa \
        -o results/"${sample}".vcf results/"${sample}".bam 2>/dev/null || exit 1

    # Compress and index VCF
    bgzip -c results/"${sample}".vcf > results/"${sample}".vcf.gz 2>/dev/null || exit 1
    tabix -p vcf results/"${sample}".vcf.gz > results/"${sample}".vcf.gz.tbi 2>/dev/null || exit 1

    # Remove uncompressed VCF
    rm -f results/"${sample}".vcf 2>/dev/null || true

done

# Collapse table (idempotent)
if [ ! -s "results/collapsed.tsv" ] || [ "$(find results -name '*.vcf.gz' | sort)" != "$(find results -name '*.vcf.gz' | sort 2>/dev/null)" ]; then
    echo "sample\tchrom\tpos\tref\talt\taf" > results/collapsed.tsv
    for sample in $SAMPLES; do
        bcftools query -f '{sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' \
            results/"${sample}".vcf.gz >> results/collapsed.tsv 2>/dev/null || true
    done
fi

exit 0