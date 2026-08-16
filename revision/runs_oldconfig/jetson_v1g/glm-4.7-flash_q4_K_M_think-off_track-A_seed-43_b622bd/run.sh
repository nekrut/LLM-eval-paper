#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
RAW_DIR="data/raw"
REF_DIR="data/ref"
RESULTS_DIR="results"

mkdir -p "$RESULTS_DIR"

# 2. Reference indexing (once)
if [[ ! -f "$REF_DIR/chrM.fa.fai" ]]; then
    samtools faidx "$REF_DIR/chrM.fa"
fi
if [[ ! -f "$REF_DIR/chrM.fa.bwt" ]]; then
    bwa index "$REF_DIR/chrM.fa"
fi

# 3-5. Per-sample alignment, sorting, and indexing
for sample in "${SAMPLES[@]}"; do
    fq1="$RAW_DIR/${sample}_1.fq.gz"
    fq2="$RAW_DIR/${sample}_2.fq.gz"
    bam="$RESULTS_DIR/${sample}.bam"
    bai="$RESULTS_DIR/${sample}.bam.bai"

    if [[ ! -f "$bai" ]]; then
        bwa mem -t "$THREADS" -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" "$fq1" "$fq2" | samtools sort -@ "$THREADS" -o "$bam"
        samtools index -@ "$THREADS" "$bam"
    fi
done

# 6. Variant calling with lofreq
for sample in "${SAMPLES[@]}"; do
    vcf="$RESULTS_DIR/${sample}.vcf"
    vcf_gz="$RESULTS_DIR/${sample}.vcf.gz"
    tbi="$RESULTS_DIR/${sample}.vcf.gz.tbi"

    if [[ ! -f "$tbi" ]]; then
        lofreq call-parallel --pp-threads "$THREADS" --verbose --ref "$REF_DIR/chrM.fa" --out "$vcf" --sig --bonf "$RESULTS_DIR/${sample}.bam"
        bgzip -c "$vcf" > "$vcf_gz"
        tabix -p vcf "$vcf_gz"
        rm "$vcf"
    fi
done

# 8. Collapse step
COLLAPSED="$RESULTS_DIR/collapsed.tsv"
if [[ ! -f "$COLLAPSED" ]] || [[ "$COLLAPSED" -ot "$RESULTS_DIR/M117-bl.vcf.gz" ]]; then
    {
        echo -e "sample\tchrom\tpos\tref\talt\taf"
        for sample in "${SAMPLES[@]}"; do
            bcftools query -f '{sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "$RESULTS_DIR/${sample}.vcf.gz"
        done
    } > "$COLLAPSED"
fi