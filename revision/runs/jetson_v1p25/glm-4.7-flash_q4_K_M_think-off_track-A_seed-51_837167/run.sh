#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
RESULTS_DIR="results"
RAW_DIR="data/raw"
REF_DIR="data/ref"
REF_FA="$REF_DIR/chrM.fa"

mkdir -p "$RESULTS_DIR"

# 2. Reference indexing (once)
if [[ ! -f "$REF_FA.fai" ]]; then
    samtools faidx "$REF_FA"
fi
if [[ ! -f "$REF_FA.bwt" ]]; then
    bwa index "$REF_FA"
fi

# 3-5. Per-sample alignment, sorting, and indexing
for SAMPLE in "${SAMPLES[@]}"; do
    FASTQ1="$RAW_DIR/${SAMPLE}_1.fq.gz"
    FASTQ2="$RAW_DIR/${SAMPLE}_2.fq.gz"
    BAM="$RESULTS_DIR/${SAMPLE}.bam"
    BAI="$RESULTS_DIR/${SAMPLE}.bam.bai"
    VCF="$RESULTS_DIR/${SAMPLE}.vcf"
    VCF_GZ="$RESULTS_DIR/${SAMPLE}.vcf.gz"
    VCF_TBI="$RESULTS_DIR/${SAMPLE}.vcf.gz.tbi"

    if [[ -f "$VCF_TBI" ]]; then
        continue
    fi

    bwa mem -t "$THREADS" -R "@RG\tID:${SAMPLE}\tSM:${SAMPLE}\tLB:${SAMPLE}\tPL:ILLUMINA" "$FASTQ1" "$FASTQ2" | \
    samtools sort -@ "$THREADS" -o "$BAM"
    samtools index -@ "$THREADS" "$BAM"

    lofreq call-parallel --pp-threads "$THREADS" -f "$REF_FA" -o "$VCF" "$BAM"
    bgzip -c "$VCF" > "$VCF_GZ"
    tabix -p vcf "$VCF_GZ"
    rm "$VCF"
done

# 8. Collapse step
COLLAPSED="$RESULTS_DIR/collapsed.tsv"
HEADER="sample\tchrom\tpos\tref\talt\taf"
TMP_COLLAPSED=$(mktemp)

echo -e "$HEADER" > "$TMP_COLLAPSED"

for SAMPLE in "${SAMPLES[@]}"; do
    VCF_GZ="$RESULTS_DIR/${SAMPLE}.vcf.gz"
    bcftools query -f '{sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "$VCF_GZ" >> "$TMP_COLLAPSED"
done

mv "$TMP_COLLAPSED" "$COLLAPSED"