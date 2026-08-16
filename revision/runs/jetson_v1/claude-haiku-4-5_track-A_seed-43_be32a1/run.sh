#!/usr/bin/env bash
set -euo pipefail

# Globals
THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
REF="data/ref/chrM.fa"
RESULTS_DIR="results"

# Create results directory
mkdir -p "$RESULTS_DIR"

# Reference indexing
if [ ! -f "${REF}.fai" ]; then
    samtools faidx "$REF"
fi

if [ ! -f "${REF}.bwt" ]; then
    bwa index "$REF"
fi

# Per-sample alignment, sorting, and indexing
for sample in "${SAMPLES[@]}"; do
    R1="data/raw/${sample}_1.fq.gz"
    R2="data/raw/${sample}_2.fq.gz"
    BAM="${RESULTS_DIR}/${sample}.bam"
    BAI="${RESULTS_DIR}/${sample}.bam.bai"
    
    if [ ! -f "$BAM" ] || [ "$R1" -nt "$BAM" ] || [ "$R2" -nt "$BAM" ] || [ "$REF" -nt "$BAM" ]; then
        bwa mem -t "$THREADS" -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" "$REF" "$R1" "$R2" \
            | samtools sort -@ "$THREADS" -o "$BAM"
    fi
    
    if [ ! -f "$BAI" ] || [ "$BAM" -nt "$BAI" ]; then
        samtools index -@ "$THREADS" "$BAM"
    fi
done

# Variant calling and VCF compression
for sample in "${SAMPLES[@]}"; do
    BAM="${RESULTS_DIR}/${sample}.bam"
    VCF="${RESULTS_DIR}/${sample}.vcf"
    VCF_GZ="${RESULTS_DIR}/${sample}.vcf.gz"
    VCF_TBI="${RESULTS_DIR}/${sample}.vcf.gz.tbi"
    
    if [ ! -f "$VCF_TBI" ] || [ "$BAM" -nt "$VCF_TBI" ] || [ "$REF" -nt "$VCF_TBI" ]; then
        lofreq call-parallel --pp-threads "$THREADS" -f "$REF" -o "$VCF" "$BAM"
        bgzip "$VCF"
        tabix -p vcf "$VCF_GZ"
    fi
done

# Collapse step
COLLAPSED="${RESULTS_DIR}/collapsed.tsv"

rebuild_collapsed=false
if [ ! -f "$COLLAPSED" ]; then
    rebuild_collapsed=true
else
    for sample in "${SAMPLES[@]}"; do
        VCF_GZ="${RESULTS_DIR}/${sample}.vcf.gz"
        if [ "$VCF_GZ" -nt "$COLLAPSED" ]; then
            rebuild_collapsed=true
            break
        fi
    done
fi

if [ "$rebuild_collapsed" = true ]; then
    temp_collapsed="${COLLAPSED}.tmp"
    
    printf "sample\tchrom\tpos\tref\talt\taf\n" > "$temp_collapsed"
    
    for sample in "${SAMPLES[@]}"; do
        VCF_GZ="${RESULTS_DIR}/${sample}.vcf.gz"
        bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "$VCF_GZ" >> "$temp_collapsed"
    done
    
    mv "$temp_collapsed" "$COLLAPSED"
fi