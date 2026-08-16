#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)

RAW_DIR="data/raw"
REF="data/ref/chrM.fa"
RES_DIR="results"

mkdir -p "$RES_DIR"

# --- 1. Reference indexing (once) ---
if [[ ! -s "${REF}.fai" ]]; then
    samtools faidx "$REF"
fi

if [[ ! -s "${REF}.bwt" || ! -s "${REF}.pac" || ! -s "${REF}.ann" || \
      ! -s "${REF}.amb" || ! -s "${REF}.sa" ]]; then
    bwa index "$REF"
fi

# --- 2-7. Per-sample alignment, indexing, and variant calling ---
for sample in "${SAMPLES[@]}"; do
    fq1="${RAW_DIR}/${sample}_1.fq.gz"
    fq2="${RAW_DIR}/${sample}_2.fq.gz"
    bam="${RES_DIR}/${sample}.bam"
    bai="${RES_DIR}/${sample}.bam.bai"
    vcf="${RES_DIR}/${sample}.vcf"
    vcfgz="${RES_DIR}/${sample}.vcf.gz"
    tbi="${RES_DIR}/${sample}.vcf.gz.tbi"

    need_align=1
    if [[ -s "$bam" && "$bam" -nt "$fq1" && "$bam" -nt "$fq2" ]]; then
        need_align=0
    fi

    if [[ "$need_align" -eq 1 ]]; then
        bwa mem -t "$THREADS" \
            -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
            "$REF" "$fq1" "$fq2" \
            | samtools sort -@ "$THREADS" -o "$bam"
    fi

    need_bai=1
    if [[ -s "$bai" && "$bai" -nt "$bam" ]]; then
        need_bai=0
    fi

    if [[ "$need_bai" -eq 1 ]]; then
        samtools index -@ "$THREADS" "$bam"
    fi

    need_call=1
    if [[ -s "$vcfgz" && -s "$tbi" && "$tbi" -nt "$bam" ]]; then
        need_call=0
    fi

    if [[ "$need_call" -eq 1 ]]; then
        rm -f "$vcf" "$vcfgz" "$tbi"
        lofreq call-parallel --pp-threads "$THREADS" -f "$REF" -o "$vcf" "$bam"
        bgzip -f "$vcf"
        tabix -p vcf "$vcfgz"
    fi
done

# --- 8. Collapse step ---
collapsed="${RES_DIR}/collapsed.tsv"

need_collapse=1
if [[ -s "$collapsed" ]]; then
    need_collapse=0
    for sample in "${SAMPLES[@]}"; do
        vcfgz="${RES_DIR}/${sample}.vcf.gz"
        if [[ "$vcfgz" -nt "$collapsed" ]]; then
            need_collapse=1
            break
        fi
    done
fi

if [[ "$need_collapse" -eq 1 ]]; then
    tmp_collapsed="${collapsed}.tmp"
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$tmp_collapsed"
    for sample in "${SAMPLES[@]}"; do
        vcfgz="${RES_DIR}/${sample}.vcf.gz"
        bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "$vcfgz" >> "$tmp_collapsed"
    done
    mv "$tmp_collapsed" "$collapsed"
fi