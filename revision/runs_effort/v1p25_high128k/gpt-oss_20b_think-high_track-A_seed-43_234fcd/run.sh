#!/usr/bin/env bash
set -euo pipefail

THREADS=4
RAW_DIR="data/raw"
REF_DIR="data/ref"
RESULTS_DIR="results"
REF_FA="${REF_DIR}/chrM.fa"

samples=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

mkdir -p "$RESULTS_DIR"

# Reference indexing
if [ ! -f "${REF_FA}.fai" ]; then
    samtools faidx "$REF_FA"
fi

if [ ! -f "${REF_FA}.amb" ]; then
    bwa index "$REF_FA"
fi

for sample in "${samples[@]}"; do
    bam="${RESULTS_DIR}/${sample}.bam"
    bai="${RESULTS_DIR}/${sample}.bam.bai"
    vcf="${RESULTS_DIR}/${sample}.vcf"
    vcf_gz="${RESULTS_DIR}/${sample}.vcf.gz"
    vcf_tbi="${RESULTS_DIR}/${sample}.vcf.gz.tbi"

    # Alignment
    if [ ! -f "$bam" ]; then
        RG="@RG\\tID:${sample}\\tSM:${sample}\\tLB:${sample}\\tPL:ILLUMINA"
        bwa mem -t $THREADS -R "$RG" "${RAW_DIR}/${sample}_1.fq.gz" "${RAW_DIR}/${sample}_2.fq.gz" | \
            samtools sort -@ $THREADS -o "$bam"
    fi

    # BAM index
    if [ ! -f "$bai" ]; then
        samtools index -@ $THREADS "$bam"
    fi

    # Variant calling and compression
    if [ ! -f "$vcf_tbi" ] || [ ! -f "$vcf_gz" ]; then
        lofreq call-parallel --pp-threads $THREADS -f "$REF_FA" -o "$vcf" "$bam"
        bgzip -c "$vcf" > "$vcf_gz"
        tabix -p vcf "$vcf_gz"
        rm -f "$vcf"
    fi
done

# Collapsed table
collapsed_file="${RESULTS_DIR}/collapsed.tsv"

needs_rebuild=false
if [ ! -f "$collapsed_file" ]; then
    needs_rebuild=true
else
    for sample in "${samples[@]}"; do
        vcf_gz="${RESULTS_DIR}/${sample}.vcf.gz"
        if [ "$(stat -c %Y "$vcf_gz")" -gt "$(stat -c %Y "$collapsed_file")" ]; then
            needs_rebuild=true
            break
        fi
    done
fi

if $needs_rebuild; then
    >"$collapsed_file"
    printf "sample\tchrom\tpos\tref\talt\taf\n" >> "$collapsed_file"
    for sample in "${samples[@]}"; do
        bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" \
            "${RESULTS_DIR}/${sample}.vcf.gz" >> "$collapsed_file"
    done
fi

exit 0