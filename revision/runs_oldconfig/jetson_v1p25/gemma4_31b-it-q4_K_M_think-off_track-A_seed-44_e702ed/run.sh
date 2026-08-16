#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
REF="data/ref/chrM.fa"
OUTDIR="results"

mkdir -p "$OUTDIR"

# Reference Indexing
if [[ ! -f "${REF}.fai" ]]; then
    samtools faidx "$REF"
fi
if [[ ! -f "${REF}.bwt" ]]; then
    bwa index "$REF"
fi

for SAMPLE in "${SAMPLES[@]}"; do
    R1="data/raw/${SAMPLE}_1.fq.gz"
    R2="data/raw/${SAMPLE}_2.fq.gz"
    BAM="${OUTDIR}/${SAMPLE}.bam"
    BAI="${BAM}.bai"
    VCF_GZ="${OUTDIR}/${SAMPLE}.vcf.gz"
    VCF_TBI="${VCF_GZ}.tbi"

    # Alignment and Sorting
    if [[ ! -f "$BAM" ]]; then
        bwa mem -t "$THREADS" -R "@RG\tID:${SAMPLE}\tSM:${SAMPLE}\tLB:${SAMPLE}\tPL:ILLUMINA" "$REF" "$R1" "$R2" | \
        samtools sort -@ "$THREADS" -o "$BAM"
    fi

    # BAM Indexing
    if [[ ! -f "$BAI" ]]; then
        samtools index -@ "$THREADS" "$BAM"
    fi

    # Variant Calling
    if [[ ! -f "$VCF_TBI" ]]; then
        lofreq call-parallel --pp-threads "$THREADS" -f "$REF" -o "${OUTDIR}/${SAMPLE}.vcf" "$BAM"
        bgzip -c "${OUTDIR}/${SAMPLE}.vcf" > "$VCF_GZ"
        tabix -p vcf "$VCF_GZ"
        rm "${OUTDIR}/${SAMPLE}.vcf"
    fi
done

# Collapsed Table
COLLAPSED="${OUTDIR}/collapsed.tsv"
REBUILD=0
if [[ ! -f "$COLLAPSED" ]]; then
    REBUILD=1
else
    for SAMPLE in "${SAMPLES[@]}"; do
        if [[ "${OUTDIR}/${SAMPLE}.vcf.gz" -nt "$COLLAPSED" ]]; then
            REBUILD=1
            break
        fi
    done
fi

if [[ $REBUILD -eq 1 ]]; then
    printf "sample\tchrom\tpos\tref\talt\taf\n" > "$COLLAPSED"
    for SAMPLE in "${SAMPLES[@]}"; do
        bcftools query -f "${SAMPLE}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "${OUTDIR}/${SAMPLE}.vcf.gz" >> "$COLLAPSED"
    done
fi