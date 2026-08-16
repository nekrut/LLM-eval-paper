#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)
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
    if [[ -f "${RES_DIR}/${sample}.vcf.gz.tbi" ]]; then
        continue
    fi

    RG_STR="@RG\\tID:${sample}\\tSM:${sample}\\tLB:${sample}\\tPL:ILLUMINA"

    bwa mem -t "$THREADS" -R "$RG_STR" "$REF" "${RAW_DIR}/${sample}_1.fq.gz" "${RAW_DIR}/${sample}_2.fq.gz" | \
        samtools sort -@ "$THREADS" -o "${RES_DIR}/${sample}.bam"

    samtools index -@ "$THREADS" "${RES_DIR}/${sample}.bam"

    lofreq call-parallel --pp-threads "$THREADS" --verbose \
        --ref "$REF" --out "${RES_DIR}/${sample}.vcf" \
        --sig --bonf "${RES_DIR}/${sample}.bam"

    bgzip -c "${RES_DIR}/${sample}.vcf" > "${RES_DIR}/${sample}.vcf.gz"
    tabix -p vcf "${RES_DIR}/${sample}.vcf.gz"
    rm "${RES_DIR}/${sample}.vcf"
done

NEEDS_COLLAPSE=false
if [[ ! -f "${RES_DIR}/collapsed.tsv" ]]; then
    NEEDS_COLLAPSE=true
else
    for sample in "${SAMPLES[@]}"; do
        if [[ "${RES_DIR}/${sample}.vcf.gz.tbi" -nt "${RES_DIR}/collapsed.tsv" ]]; then
            NEEDS_COLLAPSE=true
            break
        fi
    done
fi

if [ "$NEEDS_COLLAPSE" = true ]; then
    printf "sample\tchrom\tpos\tref\talt\taf\n" > "${RES_DIR}/collapsed.tsv"
    for sample in "${SAMPLES[@]}"; do
        bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "${RES_DIR}/${sample}.vcf.gz" >> "${RES_DIR}/collapsed.tsv"
    done
fi