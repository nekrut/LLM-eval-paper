#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
REF="data/ref/chrM.fa"
RAW_DIR="data/raw"
OUT_DIR="results"

mkdir -p "$OUT_DIR"

if [[ ! -f "${REF}.fai" ]] || [[ ! -f "${REF}.amb" ]]; then
    samtools faidx "$REF"
    bwa index "$REF"
fi

for sample in "${SAMPLES[@]}"; do
    bam_file="${OUT_DIR}/${sample}.bam"
    bai_file="${bam_file}.bai"
    vcf_gz_file="${OUT_DIR}/${sample}.vcf.gz"
    tbi_file="${vcf_gz_file}.tbi"

    if [[ -f "$tbi_file" ]]; then
        continue
    fi

    fq1="${RAW_DIR}/${sample}_1.fq.gz"
    fq2="${RAW_DIR}/${sample}_2.fq.gz"

    if [[ ! -f "$bam_file" ]]; then
        bwa mem -t "$THREADS" -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" "$REF" "$fq1" "$fq2" | \
            samtools sort -@ "$THREADS" -o "$bam_file"
    fi

    if [[ ! -f "$bai_file" ]]; then
        samtools index -@ "$THREADS" "$bam_file"
    fi

    vcf_file="${OUT_DIR}/${sample}.vcf"
    if [[ ! -f "$vcf_gz_file" ]]; then
        lofreq call-parallel --pp-threads "$THREADS" \
            --ref "$REF" --out "$vcf_file" \
            "$bam_file"
    fi

    if [[ ! -f "$tbi_file" ]]; then
        bgzip -c "$vcf_file" > "$vcf_gz_file"
        tabix -p vcf "$vcf_gz_file"
        rm -f "$vcf_file"
    fi
done

tsv_file="${OUT_DIR}/collapsed.tsv"
if [[ ! -f "$tsv_file" ]]; then
    {
        printf "sample\tchrom\tpos\tref\talt\taf\n"
        for sample in "${SAMPLES[@]}"; do
            bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "${OUT_DIR}/${sample}.vcf.gz"
        done
    } > "$tsv_file"
fi