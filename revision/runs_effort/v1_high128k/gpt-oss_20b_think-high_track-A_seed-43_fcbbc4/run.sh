#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

RAW_DIR="data/raw"
REF_DIR="data/ref"
OUT_DIR="results"

mkdir -p "$OUT_DIR"

# Reference indexing
if [ ! -f "$REF_DIR/chrM.fa.fai" ]; then
    samtools faidx "$REF_DIR/chrM.fa"
fi

if [ ! -f "$REF_DIR/chrM.fa.bwt" ]; then
    bwa index "$REF_DIR/chrM.fa"
fi

needs_run() {
    local sample="$1"
    local bam="$OUT_DIR/${sample}.bam"
    local bai="$bam.bai"
    local vcf_gz="$OUT_DIR/${sample}.vcf.gz"
    local tbi="$vcf_gz.tbi"

    if [ ! -f "$tbi" ] || [ ! -f "$bam" ] || [ ! -f "$bai" ]; then
        return 0
    fi

    local fastq1="$RAW_DIR/${sample}_1.fq.gz"
    local fastq2="$RAW_DIR/${sample}_2.fq.gz"
    local ref_fai="$REF_DIR/chrM.fa.fai"

    local latest_input_mtime=$(stat -c %Y "$fastq1")
    local tmp=$(stat -c %Y "$fastq2")
    if [ "$tmp" -gt "$latest_input_mtime" ]; then
        latest_input_mtime=$tmp
    fi
    tmp=$(stat -c %Y "$ref_fai")
    if [ "$tmp" -gt "$latest_input_mtime" ]; then
        latest_input_mtime=$tmp
    fi

    local artifact_mtime=$(stat -c %Y "$tbi")

    if [ "$artifact_mtime" -lt "$latest_input_mtime" ]; then
        return 0
    else
        return 1
    fi
}

for sample in "${SAMPLES[@]}"; do
    if needs_run "$sample"; then
        fastq1="$RAW_DIR/${sample}_1.fq.gz"
        fastq2="$RAW_DIR/${sample}_2.fq.gz"
        bam="$OUT_DIR/${sample}.bam"

        bwa mem -t "$THREADS" \
            -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
            "$fastq1" "$fastq2" | samtools sort -@ "$THREADS" -o "$bam"

        samtools index -@ "$THREADS" "$bam"

        vcf="$OUT_DIR/${sample}.vcf"
        lofreq call-parallel --pp-threads "$THREADS" \
            -f "$REF_DIR/chrM.fa" -b "$bam" > "$vcf"

        vcf_gz="${vcf}.gz"
        bgzip -c "$vcf" > "$vcf_gz"

        tabix -p vcf "$vcf_gz"

        rm "$vcf"
    fi
done

collapsed_file="$OUT_DIR/collapsed.tsv"
needs_collapse=0
if [ ! -f "$collapsed_file" ]; then
    needs_collapse=1
else
    latest_input_mtime=0
    for sample in "${SAMPLES[@]}"; do
        vcf_gz="${OUT_DIR}/${sample}.vcf.gz"
        if [ ! -f "$vcf_gz" ]; then
            needs_collapse=1
            break
        fi
        tmp=$(stat -c %Y "$vcf_gz")
        if [ "$tmp" -gt "$latest_input_mtime" ]; then
            latest_input_mtime=$tmp
        fi
    done

    collapsed_mtime=$(stat -c %Y "$collapsed_file")

    if [ "$collapsed_mtime" -lt "$latest_input_mtime" ]; then
        needs_collapse=1
    else
        needs_collapse=0
    fi
fi

if [ "$needs_collapse" -eq 1 ]; then
    printf "sample\tchrom\tpos\tref\talt\taf\n" > "$collapsed_file"
    for sample in "${SAMPLES[@]}"; do
        vcf_gz="${OUT_DIR}/${sample}.vcf.gz"
        bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "$vcf_gz" >> "$collapsed_file"
    done
fi

# End of script