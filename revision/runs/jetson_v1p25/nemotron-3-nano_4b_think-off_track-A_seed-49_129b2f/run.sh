#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES="M117-bl M117-ch M117C1-bl M117C1-ch"
RESULTS_DIR="results"

mkdir -p "$RESULTS_DIR"

# Reference indexing (idempotent)
if [[ ! -f "data/ref/chrM.fa.ind" ]] || [[ data/ref/chrM.fa.ind -nt data/ref/chrM.fa ]]; then
    samtools faidx data/ref/chrM.fa > /dev/null 2>&1
    bwa index data/ref/chrM.fa > /dev/null 2>&1
fi

# Per-sample processing
for S in $SAMPLES; do
    # Skip if all outputs exist and are up to date
    if [[ -f "results/${S}.bam" ]] && [[ -f "results/${S}.bam.ind" ]] && \
       [[ -f "results/${S}.vcf.gz" ]] && [[ -f "results/${S}.vcf.gz.tbi" ]]; then
        continue
    fi

    # Alignment
    bwa mem -t $THREADS data/raw/"${S}_1.fq.gz" data/raw/"${S}_2.fq.gz \
        > results/"${S}.bam"

    # Sort BAM
    samtools sort -@ $THREADS -o results/"${S}.bam"

    # Index BAM
    samtools index -@ $THREADS results/"${S}.bam" > /dev/null 2>&1

    # Variant calling with lofreq (parallel)
    lofreq call-parallel --pp-threads $THREADS -f data/ref/chrM.fa \
        -o results/"${S}.vcf" results/"${S}.bam"

    # Compress VCF
    bgzip -c results/"${S}.vcf" > results/"${S}.vcf.gz"
    tabix -p vcf results/"${S}.vcf.gz.tbi

    # Remove uncompressed VCF
    rm -f results/"${S}.vcf"

    # Collapse step (only if TSV is older than any input VCF)
    if [[ ! -f "results/collapsed.tsv" ]] || \
       [[ "results/${S}.vcf.gz" -nt "results/collapsed.tsv" ]]; then
        echo "sample\tchrom\tpos\tref\talt\taf" > results/collapsed.tsv
        for S2 in $SAMPLES; do
            bcftools query -f "${S2}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" \
                results/"${S2}.vcf.gz" >> results/collapsed.tsv
        done
    fi
done

exit 0