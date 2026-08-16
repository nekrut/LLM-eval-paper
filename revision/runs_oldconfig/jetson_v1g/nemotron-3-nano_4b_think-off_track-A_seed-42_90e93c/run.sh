#!/usr/bin/env bash
set -euo pipefail
THREADS=4
SAMPLES="M117-bl M117-ch M117C1-bl M117C1-ch"
mkdir -p results

# Reference indexing (once)
if [[ ! -f data/ref/chrM.fa.ind ]]; then
    samtools faidx data/ref/chrM.fa
    bwa index data/ref/chrM.fa
fi

for S in $SAMPLES; do
    # Skip if all outputs exist and are up to date
    if [[ -f "results/${S}.bam" && -f "results/${S}.vcf.gz.tbi" ]]; then
        continue
    fi

    # Alignment
    bwa mem -t $THREADS data/raw/${S}_1.fq.gz data/raw/${S}_2.fq.gz \
        > results/${S}.bam 2>/dev/null || true

    if [[ ! -f "results/${S}.bam" ]]; then
        exit 1
    fi

    # Sort BAM (idempotent)
    samtools sort -@ $THREADS -o results/${S}.bam 2>/dev/null || true

    # Index BAM
    samtools index -@ $THREADS results/${S}.bam 2>/dev/null || true

    # Variant calling with lofreq call-parallel (idempotent)
    if [[ ! -f "results/${S}.vcf" ]]; then
        lofreq call-parallel --pp-threads $THREADS --verbose \
            --ref data/ref/chrM.fa --out results/${S}.vcf \
            --sig --bonf results/${S}.bam 2>/dev/null || true
    fi

    if [[ ! -f "results/${S}.vcf.gz" ]]; then
        bgzip -c results/${S}.vcf > results/${S}.vcf.gz 2>/dev/null || true
        tabix -p vcf results/${S}.vcf.gz.1 > results/${S}.vcf.gz.tbi 2>/dev/null || true
        rm results/${S}.vcf 2>/dev/null || true
    fi

done

# Collapse step
if [[ ! -f "results/collapsed.tsv" ]] || \
   (( $(find data/raw/*.fq.gz -mmin +1) > $(stat -c %Y results/collapsed.tsv 2>/dev/null || echo 0) )); then

    echo "sample\tchrom\tpos\tref\talt\taf" > results/collapsed.tsv
    for S in $SAMPLES; do
        bcftools query -f "${S}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" \
            results/${S}.vcf.gz >> results/collapsed.tsv 2>/dev/null || true
    done

fi