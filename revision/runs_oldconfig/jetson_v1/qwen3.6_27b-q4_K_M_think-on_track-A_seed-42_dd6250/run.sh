#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)
REF="data/ref/chrM.fa"
RAW_DIR="data/raw"
OUT_DIR="results"

mkdir -p "$OUT_DIR"

# Reference indexing (idempotent)
if [[ ! -f "${REF}.fai" || ! -f "${REF}.bwt" ]]; then
    samtools faidx "$REF"
    bwa index "$REF"
fi

for sample in "${SAMPLES[@]}"; do
    bam_file="${OUT_DIR}/${sample}.bam"
    bai_file="${OUT_DIR}/${sample}.bam.bai"
    vcf_gz_file="${OUT_DIR}/${sample}.vcf.gz"
    tbi_file="${OUT_DIR}/${sample}.vcf.gz.tbi"
    
    # Skip if final artifact exists
    [[ -f "$tbi_file" ]] && continue
    
    fq1="${RAW_DIR}/${sample}_1.fq.gz"
    fq2="${RAW_DIR}/${sample}_2.fq.gz"
    
    # Alignment + sorting (idempotent)
    if [[ ! -f "$bam_file" ]]; then
        bwa mem -t "$THREADS" -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" "$REF" "$fq1" "$fq2" | \
            samtools sort -@ "$THREADS" -o "$bam_file"
    fi
    
    # BAM indexing (idempotent)
    if [[ ! -f "$bai_file" ]]; then
        samtools index -@ "$THREADS" "$bam_file"
    fi
    
    # Variant calling + compression + indexing (idempotent)
    vcf_tmp="${OUT_DIR}/${sample}.vcf"
    if [[ ! -f "$vcf_gz_file" ]]; then
        [[ -f "$vcf_tmp" ]] || lofreq call-parallel --pp-threads "$THREADS" -f "$REF" -o "$vcf_tmp" "$bam_file"
        bgzip -c "$vcf_tmp" > "$vcf_gz_file"
        tabix -p vcf "$vcf_gz_file"
        rm -f "$vcf_tmp"
    fi
done

# Collapse step -> results/collapsed.tsv
COLLAPSED_FILE="${OUT_DIR}/collapsed.tsv"
REBUILD=0

if [[ ! -f "$COLLAPSED_FILE" ]]; then
    REBUILD=1
else
    for sample in "${SAMPLES[@]}"; do
        vcf_gz="${OUT_DIR}/${sample}.vcf.gz"
        if [[ "$vcf_gz" -nt "$COLLAPSED_FILE" ]]; then
            REBUILD=1
            break
        fi
    done
fi

if [[ "$REBUILD" -eq 1 ]]; then
    {
        printf 'sample\tchrom\tpos\tref\talt\taf\n'
        for sample in "${SAMPLES[@]}"; do
            bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "${OUT_DIR}/${sample}.vcf.gz"
        done
    } > "$COLLAPSED_FILE"
fi