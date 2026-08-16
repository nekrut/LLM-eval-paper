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

# Index reference if not present
if [[ ! -f "${REF_DIR}/chrM.fa.fai" ]] || \
   [[ ! -f "$(dirname "${REF_DIR}")/chrM.fa.bwt" ]]; then
    samtools faidx "${REF_FASTA}"
    bwa index "${REF_FASTA}"
fi

# Process each sample
for SAMPLE in "${SAMPLE_LIST[@]}"; do
    # Skip if VCF.gz.tbi is newer than inputs
    INPUT_BAM="${RESULTS_DIR}/${SAMPLE}.bam"
    INPUT_VCF_TBI="${RESULTS_DIR}/${SAMPLE}.vcf.gz.tbi"
    if [[ -e "${INPUT_VCF_TBI}" ]] && \
       [[ "$(stat -c %Y "${INPUT_VCF_TBI}")" -ge "$(stat -c %Y "${RAW_DIR}/${SAMPLE}_1.fq.gz")" ]]; then
        continue
    fi

    # Align reads with bwa mem
    bwa mem -t "${THREADS}" \
        -R "@RG\tID:${SAMPLE}\tSM:${SAMPLE}\tLB:${SAMPLE}\tPL:ILLUMINA" \
        "${REF_FASTA}" \
        "${RAW_DIR}/${SAMPLE}_1.fq.gz" \
        "${RAW_DIR}/${SAMPLE}_2.fq.gz" |
    samtools sort -@ "${THREADS}" -o "${INPUT_BAM}"

    # Index BAM
    samtools index -@ "${THREADS}" "${INPUT_BAM}"

    # Call variants with lofreq
    lofreq call-parallel --pp-threads "${THREADS}" \
        -f "${REF_FASTA}" -o "${RESULTS_DIR}/${SAMPLE}.vcf" "${INPUT_BAM}"

    # Compress and index VCF
    bgzip -f "${RESULTS_DIR}/${SAMPLE}.vcf"
    tabix -p vcf "${RESULTS_DIR}/${SAMPLE}.vcf.gz"

    # Clean up uncompressed VCF
    rm "${RESULTS_DIR}/${SAMPLE}.vcf"
done

# Collapse variants into a single TSV file
{
    echo "sample\tchrom\tpos\tref\talt\taf"
    for SAMPLE in "${SAMPLE_LIST[@]}"; do
        bcftools query -f '%SAMPLE\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' \
            "${RESULTS_DIR}/${SAMPLE}.vcf.gz" >> "${RESULTS_DIR}/collapsed.tsv"
    done
} > "${RESULTS_DIR}/collapsed.tsv"

exit 0