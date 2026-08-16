#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)
REF="data/ref/chrM.fa"
RAW_DIR="data/raw"
OUT_DIR="results"

mkdir -p "$OUT_DIR"

# Reference indexing (idempotent)
if [[ ! -f "${REF}.fai" ]] || [[ ! -f "${REF}.bwt" ]]; then
    samtools faidx "$REF"
    bwa index "$REF"
fi

for sample in "${SAMPLES[@]}"; do
    # Skip if final output for this sample already exists
    if [[ -f "${OUT_DIR}/${sample}.vcf.gz.tbi" ]]; then
        continue
    fi

    R1="${RAW_DIR}/${sample}_1.fq.gz"
    R2="${RAW_DIR}/${sample}_2.fq.gz"

    # Alignment and sorting (idempotent)
    if [[ ! -f "${OUT_DIR}/${sample}.bam.bai" ]]; then
        bwa mem -t "$THREADS" -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" "$REF" "$R1" "$R2" | \
            samtools sort -@ "$THREADS" -o "${OUT_DIR}/${sample}.bam"
        samtools index -@ "$THREADS" "${OUT_DIR}/${sample}.bam"
    fi

    # Variant calling (idempotent)
    if [[ ! -f "${OUT_DIR}/${sample}.vcf.gz" ]]; then
        lofreq call-parallel --pp-threads "$THREADS" -f "$REF" -o "${OUT_DIR}/${sample}.vcf" "${OUT_DIR}/${sample}.bam"
        bgzip -c "${OUT_DIR}/${sample}.vcf" > "${OUT_DIR}/${sample}.vcf.gz"
        tabix -p vcf "${OUT_DIR}/${sample}.vcf.gz"
        rm -f "${OUT_DIR}/${sample}.vcf"
    fi
done

# Collapse step (idempotent)
needs_collapse=false
if [[ ! -f "${OUT_DIR}/collapsed.tsv" ]]; then
    needs_collapse=true
else
    for sample in "${SAMPLES[@]}"; do
        if [[ "${OUT_DIR}/${sample}.vcf.gz" -nt "${OUT_DIR}/collapsed.tsv" ]]; then
            needs_collapse=true
            break
        fi
    done
fi

if $needs_collapse; then
    {
        printf 'sample\tchrom\tpos\tref\talt\taf\n'
        for sample in "${SAMPLES[@]}"; do
            bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "${OUT_DIR}/${sample}.vcf.gz"
        done
    } > "${OUT_DIR}/collapsed.tsv"
fi