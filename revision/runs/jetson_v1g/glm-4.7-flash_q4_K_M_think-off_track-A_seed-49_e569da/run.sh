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
for sample in "${SAMPLES[@]}"; do
    INPUT_1="$RAW_DIR/${sample}_1.fq.gz"
    INPUT_2="$RAW_DIR/${sample}_2.fq.gz"
    BAM="$RESULTS_DIR/${sample}.bam"
    BAI="$RESULTS_DIR/${sample}.bam.bai"

    if [[ ! -f "$BAI" ]]; then
        bwa mem -t "$THREADS" -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" "$REF_FA" "$INPUT_1" "$INPUT_2" | samtools sort -@ "$THREADS" -o "$BAM"
        samtools index -@ "$THREADS" "$BAM"
    fi
done

# 6. Variant calling with lofreq
for sample in "${SAMPLES[@]}"; do
    VCF="$RESULTS_DIR/${sample}.vcf"
    VCF_GZ="$RESULTS_DIR/${sample}.vcf.gz"
    TBI="$RESULTS_DIR/${sample}.vcf.gz.tbi"

    if [[ ! -f "$TBI" ]]; then
        lofreq call-parallel --pp-threads "$THREADS" --verbose --ref "$REF_FA" --out "$VCF" --sig --bonf "$RESULTS_DIR/${sample}.bam"
        bgzip -c "$VCF" > "$VCF_GZ"
        tabix -p vcf "$VCF_GZ"
        rm "$VCF"
    fi
done

# 8. Collapse step
COLLAPSED="$RESULTS_DIR/collapsed.tsv"
if [[ ! -f "$COLLAPSED" ]]; then
    {
        echo -e "sample\tchrom\tpos\tref\talt\taf"
        for sample in "${SAMPLES[@]}"; do
            bcftools query -f '{sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "$RESULTS_DIR/${sample}.vcf.gz"
        done
    } > "$COLLAPSED"
fi