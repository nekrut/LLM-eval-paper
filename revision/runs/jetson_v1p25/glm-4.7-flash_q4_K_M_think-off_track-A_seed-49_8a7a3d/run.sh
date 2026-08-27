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
if [ ! -f "$REF_FA.fai" ]; then
    samtools faidx "$REF_FA"
fi
if [ ! -f "${REF_FA}.amb" ]; then
    bwa index "$REF_FA"
fi

# 3-5. Per-sample alignment and BAM processing
for sample in "${SAMPLES[@]}"; do
    INPUT_1="$RAW_DIR/${sample}_1.fq.gz"
    INPUT_2="$RAW_DIR/${sample}_2.fq.gz"
    BAM="$RESULTS_DIR/${sample}.bam"
    BAI="$RESULTS_DIR/${sample}.bam.bai"
    VCF="$RESULTS_DIR/${sample}.vcf"
    VCF_GZ="$RESULTS_DIR/${sample}.vcf.gz"
    VCF_GZ_TBI="$RESULTS_DIR/${sample}.vcf.gz.tbi"

    # Alignment
    if [ ! -f "$BAM" ]; then
        bwa mem -t "$THREADS" -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" "$INPUT_1" "$INPUT_2" | samtools sort -@ "$THREADS" -o "$BAM"
    fi

    # BAM Index
    if [ ! -f "$BAI" ]; then
        samtools index -@ "$THREADS" "$BAM"
    fi

    # Variant calling
    if [ ! -f "$VCF" ]; then
        lofreq call-parallel --pp-threads "$THREADS" -f "$REF_FA" -o "$VCF" "$BAM"
    fi

    # VCF compression and indexing
    if [ ! -f "$VCF_GZ" ]; then
        bgzip -c "$VCF" > "$VCF_GZ"
        tabix -p vcf "$VCF_GZ"
        rm "$VCF"
    fi

    if [ ! -f "$VCF_GZ_TBI" ]; then
        tabix -p vcf "$VCF_GZ"
    fi
done

# 8. Collapse step
COLLAPSED="$RESULTS_DIR/collapsed.tsv"
HEADER="sample\tchrom\tpos\tref\talt\taf"

if [ ! -f "$COLLAPSED" ]; then
    {
        echo "$HEADER"
        for sample in "${SAMPLES[@]}"; do
            bcftools query -f '{sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "$RESULTS_DIR/${sample}.vcf.gz"
        done
    } > "$COLLAPSED"
fi