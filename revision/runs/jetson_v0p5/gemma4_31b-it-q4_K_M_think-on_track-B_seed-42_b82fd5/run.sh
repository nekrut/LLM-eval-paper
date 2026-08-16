#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
REF="data/ref/chrM.fa"

mkdir -p results

if [ ! -f "${REF}.bwt" ]; then
    bwa index "$REF"
fi

if [ ! -f "${REF}.fai" ]; then
    samtools faidx "$REF"
fi

for sample in "${SAMPLES[@]}"; do
    BAM="results/${sample}.bam"
    BAI="${BAM}.bai"
    VCF_GZ="results/${sample}.vcf.gz"
    TBI="${VCF_GZ}.tbi"

    if [ ! -f "$BAM" ]; then
        bwa mem -t "$THREADS" "$REF" "data/raw/${sample}_1.fq.gz" "data/raw/${sample}_2.fq.gz" | \
        samtools sort -@ "$THREADS" -o "$BAM" -
    fi

    if [ ! -f "$BAI" ]; then
        samtools index -@ "$THREADS" "$BAM"
    fi

    if [ ! -f "$VCF_GZ" ]; then
        lofreq call -f "$REF" -b "$BAM" > "results/${sample}.vcf"
        bcftools view -Oz -o "$VCF_GZ" "results/${sample}.vcf"
        rm "results/${sample}.vcf"
    fi

    if [ ! -f "$TBI" ]; then
        tabix -p vcf "$VCF_GZ"
    fi
done

COLLAPSED="results/collapsed.tsv"
# Idempotency check for the collapsed table: regenerate if missing or if any VCF is newer than the table
REGENERATE=0
if [ ! -f "$COLLAPSED" ]; then
    REGENERATE=1
else
    for sample in "${SAMPLES[@]}"; do
        if [ "results/${sample}.vcf.gz" -nt "$COLLAPSED" ]; then
            REGENERATE=1
            break
        fi
    done
fi

if [ "$REGENERATE" -eq 1 ]; then
    printf "sample\tchrom\tpos\tref\talt\taf\n" > "$COLLAPSED"
    for sample in "${SAMPLES[@]}"; do
        bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "results/${sample}.vcf.gz" >> "$COLLAPSED"
    done
fi