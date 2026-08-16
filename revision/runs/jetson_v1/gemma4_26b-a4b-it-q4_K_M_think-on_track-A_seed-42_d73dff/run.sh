#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
REF="data/ref/chrM.fa"
RAW_DIR="data/raw"
RESULTS_DIR="results"

mkdir -p "$RESULTS_DIR"

if [[ ! -f "${REF}.fai" ]]; then
    samtools faidx "$REF"
fi

if [[ ! -t 0 ]] && [[ ! -f "${REF}.bwt" ]]; then
    bwa index "$REF"
fi

for sample in "${SAMPLES[@]}"; do
    BAM="${RESULTS_DIR}/${sample}.bam"
    BAI="${BAM}.bai"
    
    if [[ ! -f "$BAI" ]]; then
        bwa mem -t "$THREADS" \
            -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
            "$REF" \
            "${RAW_DIR}/${sample}_1.fq.gz" \
            "${RAW_DIR}/${sample}_2.fq.gz" | \
        samtools sort -@ "$THREADS" -o "$BAM"
        
        samtools index -@ "$THREADS" "$BAM"
    fi

    VCF_GZ="${RESULTS_DIR}/${sample}.vcf.gz"
    TBI="${VCF_GZ}.tbi"
    if [[ ! -f "$TBI" ]]; then
        VCF_TMP="${RESULTS_DIR}/${sample}.vcf"
        lofreq call-parallel --pp-threads "$THREADS" -f "$REF" -o "$VCF_TMP" "$BAM"
        bgzip -c "$VCF_TMP" > "$VCF_GZ"
        tabix -p vcf "$VCF_GZ"
        rm "$VCF_TMP"
    fi
done

COLLAPSED="${RESULTS_DIR}/collapsed.tsv"
NEEDS_COLLAPSE=false
if [[ ! -f "$COLLAPSED" ]]; then
    NEEDS_COLLAPSE=true
else
    for sample in "${SAMPLES[@]}"; do
        if [[ "${RESULTS_DIR}/${sample}.vcf.gz" -nt "$COLLAPSED" ]]; then
            NEEDS_COLLAPSE=true
            break
        fi
    done
fi

if [ "$NEEDS_COLLAPSE" = true ]; then
    TMP_TSV=$(mktemp)
    printf "sample\tchrom\tpos\tref\talt\taf\n" > "$TMP_TSV"
    for sample in "${SAMPLES[@]}"; do
        bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" \
            "${RESULTS_DIR}/${sample}.vcf.gz" >> "$TMP_TSV"
    done
    mv "$TMP_TSV" "$COLLAPSED"
fi

exit 0