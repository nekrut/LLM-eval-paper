#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)
REF="data/ref/chrM.fa"
RAW_DIR="data/raw"
RES_DIR="results"

mkdir -p "$RES_DIR"

# Reference indexing
if [[ ! -f "${REF}.fai" ]] || [[ ! -f "${REF}.sa" ]]; then
    samtools faidx "$REF"
    bwa index "$REF"
fi

# Per-sample pipeline
for sample in "${SAMPLES[@]}"; do
    if [[ -f "${RES_DIR}/${sample}.vcf.gz.tbi" ]]; then
        continue
    fi

    bwa mem -t "$THREADS" "$REF" \
        "${RAW_DIR}/${sample}_1.fq.gz" \
        "${RAW_DIR}/${sample}_2.fq.gz" \
        -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" | \
    samtools sort -@ "$THREADS" -o "${RES_DIR}/${sample}.bam"

    samtools index -@ "$THREADS" "${RES_DIR}/${sample}.bam"

    lofreq call-parallel --pp-threads "$THREADS" \
        -f "$REF" \
        -o "${RES_DIR}/${sample}.vcf" \
        "${RES_DIR}/${sample}.bam"

    bgzip -c "${RES_DIR}/${sample}.vcf" > "${RES_DIR}/${sample}.vcf.gz"
    tabix -p vcf "${RES_DIR}/${sample}.vcf.gz"
    
    rm -f "${RES_DIR}/${sample}.vcf"
done

# Collapse step
NEED_UPDATE=false
if [[ ! -f "${RES_DIR}/collapsed.tsv" ]]; then
    NEED_UPDATE=true
else
    for sample in "${SAMPLES[@]}"; do
        if [[ "${RES_DIR}/${sample}.vcf.gz" -nt "${RES_DIR}/collapsed.tsv" ]]; then
            NEED_UPDATE=true
            break
        fi
    done
fi

if [[ "$NEED_UPDATE" == true ]]; then
    {
        printf "sample\tchrom\tpos\tref\talt\taf\n"
        for sample in "${SAMPLES[@]}"; do
            bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "${RES_DIR}/${sample}.vcf.gz"
        done
    } > "${RES_DIR}/collapsed.tsv"
fi