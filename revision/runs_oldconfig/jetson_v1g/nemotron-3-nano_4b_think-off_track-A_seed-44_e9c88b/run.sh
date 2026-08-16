#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES="M117-bl M117-ch M117C1-bl M117C1-ch"
RESULTS_DIR="results"

mkdir -p "$RESULTS_DIR"

# Reference indexing (idempotent)
if [ ! -f "data/ref/chrM.fa.ind" ] || [ data/ref/chrM.fa.ind -nt data/ref/chrM.fa ]; then
    samtools faidx data/ref/chrM.fa > /dev/null 2>&1
    bwa index data/ref/chrM.fa > /dev/null 2>&1
fi

# Per-sample processing
for sample in $SAMPLES; do
    # Skip if all outputs exist and are up to date
    if [ -f "results/${sample}.vcf.gz.tbi" ] && [ -f "results/${sample}.bam.ind" ]; then
        continue
    fi

    # Alignment
    bwa mem -t $THREADS data/raw/"$sample"_1.fq.gz data/raw/"$sample"_2.fq.gz \
        > results/"${sample}".bam 2>/dev/null || exit 1

    # Sort BAM (idempotent: samtools sort will skip if already sorted and newer)
    samtools sort -@ $THREADS -o results/"${sample}".bam 2>/dev/null || exit 1

    # Index BAM
    samtools index -@ $THREADS results/"${sample}".bam > /dev/null 2>&1

    # Variant calling with lofreq call-parallel (idempotent: skips if VCF exists and newer)
    if [ ! -f "results/${sample}.vcf" ] || [ "results/${sample}.vcf" -nt "results/${sample}.bam.ind" ]; then
        lofreq call-parallel --pp-threads $THREADS --verbose \
            --ref data/ref/chrM.fa --out results/"${sample}".vcf \
            --sig --bonf results/"${sample}".bam 2>/dev/null || exit 1
    fi

    # Compress and index VCF (idempotent: skip if .gz.tbi exists and is newer than inputs)
    if [ ! -f "results/${sample}.vcf.gz" ] || [ "results/${sample}.vcf.gz" -nt "results/${sample}.vcf" ]; then
        bgzip results/"${sample}".vcf > /dev/null 2>&1
        tabix -p vcf results/"${sample}".vcf.gz > /dev/null 2>&1
        rm -f results/"${sample}".vcf
    fi

done

# Collapse step (idempotent: rebuild only if any VCF is newer than TSV)
if [ ! -f "results/collapsed.tsv" ] || [ "results/collapsed.tsv" -nt "results/${SAMPLES[0]}.vcf.gz" ]; then
    echo -e "sample\tchrom\tpos\tref\talt\taf" > results/collapsed.tsv
    for sample in $SAMPLES; do
        bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" \
            results/"${sample}".vcf.gz >> results/collapsed.tsv 2>/dev/null || true
    done
fi

exit 0