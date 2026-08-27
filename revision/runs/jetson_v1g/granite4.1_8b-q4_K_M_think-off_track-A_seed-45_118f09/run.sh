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
if [[ ! -e "${REF_DIR}/chrM.fa.fai" ]] || \
   [[ ! -e "${REF_DIR}/chrM.fa.amb" ]] || \
   [[ ! -e "${REF_DIR}/chrM.fa.ann" ]] || \
   [[ ! -e "${REF_DIR}/chrM.fa.bwt" ]] || \
   [[ ! -e "${REF_DIR}/chrM.fa.pac" ]] || \
   [[ ! -e "${REF_DIR}/chrM.fa.sa" ]]; then
    samtools faidx "${REF_FASTA}"
    bwa index "${REF_FASTA}"
fi

# Per-sample alignment and variant calling
for SAMPLE in "${SAMPLE_LIST[@]}"; do
    # Skip if VCF already exists and is up-to-date
    if [[ -e "${RESULTS_DIR}/${SAMPLE}.vcf.gz.tbi" ]]; then
        continue
    fi

    # Alignment with bwa mem (idempotent)
    bwa mem -t "${THREADS}" \
        -R "@RG\tID:${SAMPLE}\tSM:${SAMPLE}\tLB:${SAMPLE}\tPL:ILLUMINA" \
        "${REF_FASTA}" \
        "${RAW_DIR}/${SAMPLE}_1.fq.gz" \
        "${RAW_DIR}/${SAMPLE}_2.fq.gz" |
    samtools sort -@ "${THREADS}" -o "${RESULTS_DIR}/${SAMPLE}.bam"

    # BAM indexing
    samtools index -@ "${THREADS}" "${RESULTS_DIR}/${SAMPLE}.bam"

    # Variant calling with lofreq
    lofreq call-parallel --pp-threads "${THREADS}" \
        --ref "${REF_FASTA}" \
        --out "${RESULTS_DIR}/${SAMPLE}.vcf" \
        "${RESULTS_DIR}/${SAMPLE}.bam"

    # VCF compression and indexing
    bgzip -f "${RESULTS_DIR}/${SAMPLE}.vcf"
    tabix -p vcf "${RESULTS_DIR}/${SAMPLE}.vcf.gz"
    rm "${RESULTS_DIR}/${SAMPLE}.vcf"

    # Append sample name to bcftools query format string via printf substitution
    SAMPLE_NAME="${SAMPLE}"
    bcftools query -f "${SAMPLE_NAME}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" \
        "${RESULTS_DIR}/${SAMPLE}.vcf.gz"
done | while IFS=$'\t' read -r sample chrom pos ref alt af; do
    [[ -z "$sample" ]] && continue
    echo -e "sample\tchrom\tpos\tref\talt\taf"
    printf "%s\t%s\t%s\t%s\t%s\t%s\n" "${sample}" "${chrom}" "${pos}" "${ref}" "${alt}" "${af}"
done > "${RESULTS_DIR}/collapsed.tsv"

exit 0