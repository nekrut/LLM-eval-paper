#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES="M117-bl M117-ch M117C1-bl M117C1-ch"
REF="data/ref/chrM.fa"
RESULTS_DIR="results"

mkdir -p "$RESULTS_DIR"

# Reference indexing
if [[ ! -f "${REF}.fai" ]]; then
    samtools faidx "$REF"
fi

if [[ ! -f "${REF}.bwt" ]]; then
    bwa index "$REF"
fi

for sample in $SAMPLES; do
    RAW1="data/raw/${sample}_1.fq.gz"
    RAW2="data/raw/${sample}_2.fq.gz"
    BAM="${RESULTS_DIR}/${sample}.bam"
    BAI="${BAM}.bai"
    VCF_PLAIN="${RESULTS_DIR}/${sample}.vcf"
    VCF_GZ="${VCF_PLAIN}.gz"
    VCF_TBI="${VCF_GZ}.tbi"

    # Alignment and Sorting
    if [[ ! -f "$BAI" ]]; then
        bwa mem -t "$THREADS" -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" "$REF" "$RAW1" "$RAW2" | \
        samtools sort -@ "$THREADS" -o "$BAM"
        samtools index -@ "$THREADS" "$BAM"
    fi

    # Variant Calling
    if [[ ! -f "$VCF_TBI" ]]; then
        lofreq call-parallel --pp-threads "$THREADS" -f "$REF" -b "$BAM" > "$VCF_PLAIN"
        bgzip -f "$VCF_PLAIN"
        tabix -p vcf "$VCF_GZ"
    fi
done

# Collapsed table
COLLAPSED="${RESULTS_DIR}/collapsed.tsv"
NEEDS_UPDATE=0
if [[ ! -f "$COLLAPSED" ]]; then
    NEEDS_UPDATE=1
else
    for sample in $SAMPLES; do
        if [[ "${RESULTS_DIR}/${sample}.vcf.gz" -nt "$COLLAPSED" ]]; then
            NEEDS_UPDATE=1
            break
        fi
    done
fi

if [[ "$NEEDS_UPDATE" -eq 1 ]]; then
    printf "sample\tchrom\tpos\tref\talt\taf\n" > "$COLLAPSED"
    for sample in $SAMPLES; do
        bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "${RESULTS_DIR}/${sample}.vcf.gz" >> "$COLLAPSED"
    done
fi