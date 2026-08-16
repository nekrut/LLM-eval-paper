#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
REF="data/ref/chrM.fa"
RAW_DIR="data/raw"
RESULTS_DIR="results"

mkdir -p "$RESULTS_DIR"

if [ ! -f "${REF}.bwt" ]; then
    bwa index "$REF"
fi

if [ ! -f "${REF}.fai" ]; then
    samtools faidx "$REF"
fi

for SAMPLE in "${SAMPLES[@]}"; do
    R1="${RAW_DIR}/${SAMPLE}_1.fq.gz"
    R2="${RAW_DIR}/${SAMPLE}_2.fq.gz"
    BAM="${RESULTS_DIR}/${SAMPLE}.bam"
    VCF_UNCOMPRESSED="${RESULTS_DIR}/${SAMPLE}.vcf"
    VCF="${RESULTS_DIR}/${SAMPLE}.vcf.gz"
    
    if [ ! -f "$BAM" ]; then
        bwa mem -t "$THREADS" "$REF" "$R1" "$R2" | \
        samtools sort -@ "$THREADS" -o "$BAM" -
    fi
    
    if [ ! -f "${BAM}.bai" ]; then
        samtools index "$BAM"
    fi
    
    if [ ! -f "$VCF" ]; then
        lofreq call --ref "$REF" -o "$VCF_UNCOMPRESSED" "$BAM"
        bgzip -f "$VCF_UNCOMPRESSED"
    fi
    
    if [ ! -f "${VCF}.tbi" ]; then
        tabix -p vcf "$VCF"
    fi
done

if [ ! -f "${RESULTS_DIR}/collapsed.tsv" ]; then
    printf "sample\tchrom\tpos\tref\talt\taf\n" > "${RESULTS_DIR}/collapsed.tsv"
    
    for SAMPLE in "${SAMPLES[@]}"; do
        VCF="${RESULTS_DIR}/${SAMPLE}.vcf.gz"
        if [ -f "$VCF" ]; then
            bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "$VCF" | \
            awk -v OFS='\t' -v sample="$SAMPLE" '{print sample, $1, $2, $3, $4, $5}' >> "${RESULTS_DIR}/collapsed.tsv"
        fi
    done
fi