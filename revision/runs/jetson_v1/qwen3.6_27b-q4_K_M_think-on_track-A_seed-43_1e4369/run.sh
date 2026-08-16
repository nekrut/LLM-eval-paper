#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
REF="data/ref/chrM.fa"
RAW_DIR="data/raw"
RES_DIR="results"

mkdir -p "$RES_DIR"

# Reference indexing (idempotent)
if [[ ! -f "${REF}.fai" ]] || [[ ! -f "${REF}.amb" ]]; then
    samtools faidx "$REF"
    bwa index "$REF"
fi

for sample in "${SAMPLES[@]}"; do
    BAM="${RES_DIR}/${sample}.bam"
    BAI="${BAM}.bai"
    VCF_GZ="${RES_DIR}/${sample}.vcf.gz"
    TBI="${VCF_GZ}.tbi"

    # Skip entire sample pipeline if final index exists
    [[ -f "$TBI" ]] && continue

    R1="${RAW_DIR}/${sample}_1.fq.gz"
    R2="${RAW_DIR}/${sample}_2.fq.gz"

    # Alignment + sorting
    if [[ ! -f "$BAM" ]]; then
        bwa mem -t "$THREADS" -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" "$REF" "$R1" "$R2" | \
            samtools sort -@ "$THREADS" -o "$BAM"
    fi

    # BAM indexing
    if [[ ! -f "$BAI" ]]; then
        samtools index -@ "$THREADS" "$BAM"
    fi

    # Variant calling + compression + indexing
    VCF_TMP="${RES_DIR}/${sample}.vcf"
    if [[ ! -f "$VCF_GZ" ]]; then
        lofreq call-parallel --pp-threads "$THREADS" -f "$REF" -o "$VCF_TMP" "$BAM"
        bgzip -c "$VCF_TMP" > "$VCF_GZ"
        tabix -p vcf "$VCF_GZ"
        rm -f "$VCF_TMP"
    fi
done

# Collapse step (idempotent)
TSV="${RES_DIR}/collapsed.tsv"
if [[ ! -f "$TSV" ]]; then
    {
        printf "sample\tchrom\tpos\tref\talt\taf\n"
        for sample in "${SAMPLES[@]}"; do
            bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "${RES_DIR}/${sample}.vcf.gz"
        done
    } > "$TSV"
fi