#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES="M117-bl M117-ch M117C1-bl M117C1-ch"
RESULTS_DIR="results"

mkdir -p "$RESULTS_DIR" 2>/dev/null || exit 0

# Reference indexing (idempotent)
if [ ! -f "data/ref/chrM.fa.indx" ] || [ ! -f "data/ref/chrM.amb" ]; then
    samtools faidx data/ref/chrM.fa > /dev/null 2>&1
    bwa index data/ref/chrM.fa > /dev/null 2>&1
fi

# Per-sample processing
for S in $SAMPLES; do
    # Skip if all outputs exist and are up to date
    if [ -f "results/${S}.bam" ] && [ -f "results/${S}.vcf.gz" ] && [ -f "results/${S}.vcf.gz.tbi" ]; then
        continue
    fi

    # Alignment
    bwa mem -t $THREADS data/raw/"${S}_1.fq.gz" data/raw/"${S}_2.fq.gz \
        > results/"${S}.bam"

    # Sort BAM
    samtools sort -@ $THREADS -o results/"${S}.bam"

    # Index BAM
    samtools index -@ $THREADS results/"${S}.bam" 2>/dev/null || exit 0

    # Variant calling (parallel)
    lofreq call-parallel --pp-threads $THREADS \
        --ref data/ref/chrM.fa \
        --input results/"${S}.bam" \
        --output results/"${S}.vcf"

    # Compress and index VCF
    bgzip -c results/"${S}.vcf" > results/"${S}.vcf.gz"
    tabix -p vcf results/"${S}.vcf.gz" 2>/dev/null || exit 0
    rm results/"${S}.vcf"

    # Collapse step (only if needed)
    if [ ! -f "results/collapsed.tsv" ] || [ "$(stat -c %Y results/${S}.vcf.gz)" -gt "$(stat -c %Y results/collapsed.tsv 2>/dev/null || echo 0)" ]; then
        bcftools query -f "${S}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" \
            results/"${S}.vcf.gz" >> results/collapsed.tsv
    fi

done

# Final header if TSV is empty or missing
if [ ! -s "results/collapsed.tsv" ]; then
    echo -e "sample\tchrom\tpos\tref\talt\taf" > results/collapsed.tsv
fi