#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
REF_DIR="data/ref"
RAW_DIR="data/raw"
RESULTS_DIR="results"

mkdir -p "${RESULTS_DIR}"

# Index reference if not present
if [[ ! -f "${REF_DIR}/chrM.fa.fai" ]] || \
   [[ ! -f "$(ls ${REF_DIR}/*.bwt 2>/dev/null)" ]]; then
    samtools faidx "${REF_DIR}/chrM.fa"
    bwa index "${REF_DIR}/chrM.fa"
fi

for SAMPLE in "${SAMPLES[@]}"; do
    # Skip if output already exists and is up-to-date
    OUT_VCF_GZ="${RESULTS_DIR}/${SAMPLE}.vcf.gz"
    if [[ -e "${OUT_VCF_GZ}" ]] && \
       [[ "$(stat -c %Y "${RAW_DIR}/${SAMPLE}_1.fq.gz")" -le "$(stat -c %Y "${OUT_VCF_GZ}")" ]]; then
        continue
    fi

    # Align reads with bwa mem
    bwa mem -t "${THREADS}" \
        -R "@RG\tID:${SAMPLE}\tSM:${SAMPLE}\tLB:${SAMPLE}\tPL:ILLUMINA" \
        "${REF_DIR}/chrM.fa" \
        "${RAW_DIR}/${SAMPLE}_1.fq.gz" \
        "${RAW_DIR}/${SAMPLE}_2.fq.gz" |
    samtools sort -@ "${THREADS}" -o "${RESULTS_DIR}/${SAMPLE}.bam"

    # Index BAM
    samtools index -@ "${THREADS}" "${RESULTS_DIR}/${SAMPLE}.bam"

    # Call variants with lofreq
    lofreq call-parallel --pp-threads "${THREADS}" \
        -f "${REF_DIR}/chrM.fa" -o "${RESULTS_DIR}/${SAMPLE}.vcf" \
        "${RESULTS_DIR}/${SAMPLE}.bam"

    # Compress and index VCF, then remove uncompressed VCF
    bgzip "${RESULTS_DIR}/${SAMPLE}.vcf"
    tabix -p vcf "${RESULTS_DIR}/${SAMPLE}.vcf.gz"
    rm "${RESULTS_DIR}/${SAMPLE}.vcf"

done

# Collapse variants into a single TSV file
{
    echo "sample\tchrom\tpos\tref\talt\taf"
    for SAMPLE in "${SAMPLES[@]}"; do
        bcftools query -f '%SAMPLE\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' \
            "${RESULTS_DIR}/${SAMPLE}.vcf.gz"
    done
} > "${RESULTS_DIR}/collapsed.tsv"

exit 0