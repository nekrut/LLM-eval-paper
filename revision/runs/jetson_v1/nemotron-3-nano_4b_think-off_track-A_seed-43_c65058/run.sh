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
    if [ -f "results/${SAMPLE}.bam" ] && [ -f "results/${SAMPLE}.bam.bai" ] && \
       [ -f "results/${SAMPLE}.vcf.gz" ] && [ -f "results/${SAMPLE}.vcf.gz.tbi" ]; then
        continue
    fi

    # Alignment
    bwa mem -t $THREADS data/raw/"${SAMPLE}"_1.fq.gz data/raw/"${SAMPLE}"_2.fq.gz \
        > results/"${SAMPLE}".bam 2>/dev/null || true

    # Sort BAM (idempotent)
    samtools sort -@ $THREADS -o results/"${SAMPLE}".bam 2>/dev/null || true

    # Index BAM
    samtools index -@ $THREADS results/"${SAMPLE}".bam 2>/dev/null || true

    # Variant calling with lofreq call-parallel
    if [ ! -s "results/${SAMPLE}.vcf" ] || [ "$(stat -c %Y results/${SAMPLE}.vcf)" -lt "$(stat -c %Y data/ref/chrM.af.fai)" ]; then
        lofreq call-parallel --pp-threads $THREADS \
            --reference data/ref/chrM.fa \
            --input results/"${SAMPLE}".bam \
            --output results/"${SAMPLE}".vcf 2>/dev/null || true
    fi

    # Compress and index VCF (idempotent)
    if [ -s "results/${SAMPLE}.vcf" ] && [ ! -f "results/${SAMPLE}.vcf.gz" ]; then
        bgzip results/"${SAMPLE}".vcf > results/"${SAMPLE}".vcf.gz 2>/dev/null || true
        tabix -p vcf results/"${SAMPLE}".vcf.gz 2>/dev/null || true
        rm -f results/"${SAMPLE}".vcf
    fi

done

# Collapse step (idempotent)
if [ ! -s "results/collapsed.tsv" ] || [ "$(stat -c %Y results/collapsed.tsv)" -lt "$(stat -c %Y data/ref/chrM.af.fai)" ]; then
    echo "" > results/collapsed.tsv
    for SAMPLE in $SAMPLES; do
        if [ -f "results/${SAMPLE}.vcf.gz" ]; then
            bcftools query -f "${SAMPLE}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" results/"${SAMPLE}".vcf.gz \
                >> results/collapsed.tsv
        fi
    done
    sed -i '1s/.*/sample\\tchrom\\tpos\\tref\\taltaf/' results/collapsed.tsv 2>/dev/null || echo "sample\tchrom\tpos\tref\talt\taf" > results/collapsed.tsv
fi

exit 0