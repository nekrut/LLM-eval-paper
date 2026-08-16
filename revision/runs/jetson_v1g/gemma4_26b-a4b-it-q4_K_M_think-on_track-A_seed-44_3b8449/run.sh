#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
REF="data/ref/chrM.fa"
RAW_DIR="data/raw"
RES_DIR="results"

mkdir -p "$RES_DIR"

if [[ ! -f "${REF}.fai" ]]; then
    samtools faidx "$REF"
fi

if [[ ! -f "${REF}.bwt" ]]; then
    bwa index "$REF"
fi

for sample in "${SAMPLES[@]}"; do
    VCF_GZ="${RES_DIR}/${sample}.vcf.gz"
    TBI="${VCF_GZ}.tbi"
    BAM="${RES_DIR}/${sample}.bam"

    if [[ -f "$TBI" ]]; then
        continue
    fi

    RG_STR="@RG\\tID:${sample}\\tSM:${sample}\\tLB:${annot_lb:-${sample}}\\tPL:ILLUMINA"
    # Note: The prompt specifies the exact form for RG. 
    # We use double backslashes so that the shell passes a literal \t to bwa.
    RG_STR="@RG\\tID:${sample}\\tSM:${sample}\\tLB:${sample}\\tPL:ILLUMINA"

    bwa mem -t "$THREADS" -R "$RG_STR" \
        "${RAW_DIR}/${sample}_1.fq.gz" \
        "${RAW_DIR}/${sample}_2.fq.gz" | \
    samtools sort -@ "$THREADS" -o "$BAM"

    samtools index -@ "$THREADS" "$BAM"

    lofreq call-parallel --pp-threads "$THREADS" --verbose \
        --ref "$REF" \
        --out "${RES_DIR}/${sample}.vcf" \
        --sig --bonf \
        "$BAM"

    bgzip -f "${RES_DIR}/${sample}.vcf"
    tabix -p vcf "$VCF_GZ"
done

COLLAPSED="${RES_DIR}/collapsed.tsv"
REBUILD_TSV=false

if [[ ! -f "$COLLAPSED" ]]; then
    REBUILD_TSV=true
else
    for sample in "${SAMPLES[@]}"; do
        if [[ "${RES_DIR}/${sample}.vcf.gz" -nt "$COLLAPSED" ]]; then
            REBUILD_TSV=true
            break
        fi
    done
fi

if [ "$REBUILD_TSV" = true ]; then
    printf "sample\tchrom\tpos\tref\talt\taf\n" > "$COLLAPSED"
    for sample in "${SAMPLES[@]}"; do
        bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" \
            "${RES_DIR}/${sample}.vcf.gz" >> "$COLLAPSED"
    done
fi