#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLE_LIST=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
RESULTS_DIR="results"
RAW_DIR="data/raw"
REF_DIR="data/ref"
REF_FASTA="${REF_DIR}/chrM.fa"

# Ensure results directory exists
mkdir -p "${RESULTS_DIR}"

# Reference indexing (idempotent)
if [[ ! -f "${REF_DIR}/chrM.fa.fai" ]] || \
   [[ ! -f "$(bwa index --version < /dev/null | awk '{print $NF ".amb"}' <<<$(bwa index -h))" ]]; then
    samtools faidx "${REF_FASTA}"
    bwa index "${REF_FASTA}"
fi

# Per-sample alignment and variant calling
for SAMPLE in "${SAMPLE_LIST[@]}"; do
    # Alignment with bwa mem (idempotent)
    if [[ ! -f "${RESULTS_DIR}/${SAMPLE}.bam" ]] || \
       ([[ -s "${RAW_DIR}/${SAMPLE}_1.fq.gz" && $(stat -c%s "${RAW_DIR}/${SAMPLE}_1.fq.gz") -gt 0 ]]) || \
       ([[ -s "${RAW_DIR}/${SAMPLE}_2.fq.gz" && $(stat -c%s "${RAW_DIR}/${SAMPLE}_2.fq.gz") -gt 0 ]]); then
        bwa mem -t "${THREADS}" -R "@RG\tID:${SAMPLE}\tSM:${SAMPLE}\tLB:${SAMPLE}\tPL:ILLUMINA" \
                 "${REF_FASTA}" "${RAW_DIR}/${SAMPLE}_1.fq.gz" "${RAW_DIR}/${SAMPLE}_2.fq.gz" |
        samtools sort -@ "${THREADS}" -o "${RESULTS_DIR}/${SAMPLE}.bam"
    fi

    # BAM indexing (idempotent)
    if [[ ! -f "${RESULTS_DIR}/${SAMPLE}.bam.bai" ]] || \
       ([[ -s "${RESULTS_DIR}/${SAMPLE}.bam" && $(stat -c%s "${RESULTS_DIR}/${SAMPLE}.bam") -gt 0 ]]); then
        samtools index -@ "${THREADS}" "${RESULTS_DIR}/${SAMPLE}.bam"
    fi

    # Variant calling with lofreq (idempotent)
    if [[ ! -f "${RESULTS_DIR}/${SAMPLE}.vcf.gz" ]] || \
       ([[ -s "${RESULTS_DIR}/${SAMPLE}.bam" && $(stat -c%s "${RESULTS_DIR}/${SAMPLE}.bam") -gt 0 ]]); then
        lofreq call-parallel --pp-threads "${THREADS}" --ref "${REF_FASTA}" --out "${RESULTS_DIR}/${SAMPLE}.vcf" \
                             results/${SAMPLE}.bam
        mv "${RESULTS_DIR}/${SAMPLE}.vcf.gz" "${RESULTS_DIR}/${SAMPLE}.vcf.gz"
        tabix -p vcf "${RESULTS_DIR}/${SAMPLE}.vcf.gz"
        rm "${RESULTS_DIR}/${SAMPLE}.vcf"
    fi
done

# Collapse step to results/collapsed.tsv (idempotent)
if [[ ! -f "${RESULTS_DIR}/collapsed.tsv" ]] || \
   any_newer=$(find "${RESULTS_DIR}"/*.vcf.gz -newer "${RESULTS_DIR}/collapsed.tsv"); then
    echo "sample\tchrom\tpos\tref\talt\taf" > "${RESULTS_DIR}/collapsed.tsv"
    for SAMPLE in "${SAMPLE_LIST[@]}"; do
        bcftools query -f '%SAMPLE\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "${RESULTS_DIR}/${SAMPLE}.vcf.gz" >> "${RESULTS_DIR}/collapsed.tsv"
    done
fi

exit 0