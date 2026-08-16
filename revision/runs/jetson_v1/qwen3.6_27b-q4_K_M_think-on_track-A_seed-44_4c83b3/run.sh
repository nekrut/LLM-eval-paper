#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)
REF="data/ref/chrM.fa"
RAW_DIR="data/raw"
RESULTS_DIR="results"

mkdir -p "$RESULTS_DIR"

# Reference indexing (idempotent)
if [[ ! -f "${REF}.fai" ]] || [[ ! -f "${REF}.amb" ]]; then
    samtools faidx "$REF"
    bwa index "$REF"
fi

for sample in "${SAMPLES[@]}"; do
    R1="${RAW_DIR}/${sample}_1.fq.gz"
    R2="${RAW_DIR}/${sample}_2.fq.gz"
    BAM="${RESULTS_DIR}/${sample}.bam"
    BAI="${BAM}.bai"
    VCF_GZ="${RESULTS_DIR}/${sample}.vcf.gz"
    TBI="${VCF_GZ}.tbi"

    # Alignment and sorting (idempotent)
    if [[ ! -f "$BAM" ]] || [[ "$R1" -nt "$BAM" ]] || [[ "$R2" -nt "$BAM" ]]; then
        bwa mem -t "$THREADS" -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" "$REF" "$R1" "$R2" | \
            samtools sort -@ "$THREADS" -o "$BAM"
    fi

    # BAM indexing (idempotent)
    if [[ ! -f "$BAI" ]] || [[ "$BAM" -nt "$BAI" ]]; then
        samtools index -@ "$THREADS" "$BAM"
    fi

    # Variant calling (idempotent)
    if [[ ! -f "$TBI" ]] || [[ "$BAM" -nt "$TBI" ]]; then
        VCF_TMP="${RESULTS_DIR}/${sample}.vcf"
        lofreq call-parallel --pp-threads "$THREADS" -f "$REF" -o "$VCF_TMP" "$BAM"
        bgzip -c "$VCF_TMP" > "$VCF_GZ"
        tabix -p vcf "$VCF_GZ"
        rm -f "$VCF_TMP"
    fi
done

# Collapse step (idempotent)
COLLAPSED="${RESULTS_DIR}/collapsed.tsv"
NEED_REBUILD=false

if [[ ! -f "$COLLAPSED" ]]; then
    NEED_REBUILD=true
else
    for sample in "${SAMPLES[@]}"; do
        VCF_GZ="${RESULTS_DIR}/${sample}.vcf.gz"
        if [[ "$VCF_GZ" -nt "$COLLAPSED" ]]; then
            NEED_REBUILD=true
            break
        fi
    done
fi

if $NEED_REBUILD; then
    {
        printf 'sample\tchrom\tpos\tref\talt\taf\n'
        for sample in "${SAMPLES[@]}"; do
            VCF_GZ="${RESULTS_DIR}/${sample}.vcf.gz"
            bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "$VCF_GZ"
        done
    } > "$COLLAPSED"
fi