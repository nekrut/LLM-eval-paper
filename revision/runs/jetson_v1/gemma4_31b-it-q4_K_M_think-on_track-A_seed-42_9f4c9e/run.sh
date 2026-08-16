#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
REF="data/ref/chrM.fa"

mkdir -p results

# Reference Indexing
if [[ ! -f "${REF}.fai" ]]; then
    samtools faidx "$REF"
fi

if [[ ! -f "${REF}.bwt" ]]; then
    bwa index "$REF"
fi

for sample in "${SAMPLES[@]}"; do
    # Alignment and Sorting
    BAM="results/${sample}.bam"
    BAI="${BAM}.bai"
    R1="data/raw/${sample}_1.fq.gz"
    R2="data/raw/${sample}_2.fq.gz"

    if [[ ! -f "$BAM" ]]; then
        bwa mem -t "$THREADS" \
            -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
            "$REF" "$R1" "$R2" | \
            samtools sort -@ "$THREADS" -o "$BAM"
    fi

    # BAM Indexing
    if [[ ! -f "$BAI" ]]; then
        samtools index -@ "$THREADS" "$BAM"
    fi

    # Variant Calling
    VCF_GZ="results/${sample}.vcf.gz"
    VCF_TBI="${VCF_GZ}.tbi"
    VCF_RAW="results/${sample}.vcf"

    if [[ ! -f "$VCF_TBI" ]]; then
        lofreq call-parallel --pp-threads "$THREADS" \
            -r "$REF" \
            -b "$BAM" > "$VCF_RAW"
        
        bgzip -f "$VCF_RAW"
        tabix -p vcf "$VCF_GZ"
        rm -f "$VCF_RAW"
    fi
done

# Collapsed Table
COLLAPSED="results/collapsed.tsv"
REBUILD=false

if [[ ! -f "$COLLAPSED" ]]; then
    REBUILD=true
else
    for sample in "${SAMPLES[@]}"; do
        if [[ "results/${sample}.vcf.gz" -nt "$COLLAPSED" ]]; then
            REBUILD=true
            break
        fi
    done
fi

if [ "$REBUILD" = true ]; then
    printf "sample\tchrom\tpos\tref\talt\taf\n" > "$COLLAPSED"
    for sample in "${SAMPLES[@]}"; do
        bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "results/${sample}.vcf.gz" >> "$COLLAPSED"
    done
fi