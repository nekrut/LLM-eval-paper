#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLE_LIST=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
REF_PATH="data/ref/chrM.fa"
RAW_DIR="data/raw/"
RESULTS_DIR="results/"

mkdir -p "${RESULTS_DIR}"

# Ensure reference index exists
if [[ ! -f "${REF_PATH}.fai" ]] || \
   [[ ! -f "$(dirname "${REF_PATH}")/$(basename "${REF_PATH}" .fa).amb" ]]; then
    samtools faidx "${REF_PATH}"
    bwa index "${REF_PATH}"
fi

for SAMPLE in "${SAMPLE_LIST[@]}"; do
    # Skip if VCF and its index are up-to-date
    if [[ -f "${RESULTS_DIR}/${SAMPLE}.vcf.gz.tbi" ]] && \
       [[ "${RESULTS_DIR}/${SAMPLE}.vcf.gz.tbi" -nt "${RAW_DIR}/${SAMPLE}_1.fq.gz" ]]; then
        continue
    fi

    # Align reads with bwa mem
    bwa mem -t "${THREADS}" -R "@RG\tID:${SAMPLE}\tSM:${SAMPLE}\tLB:${SAMPLE}\tPL:ILLUMINA" \
        "${RAW_DIR}/${SAMPLE}_1.fq.gz" "${RAW_DIR}/${SAMPLE}_2.fq.gz" | \
        samtools sort -@ "${THREADS}" -o "${RESULTS_DIR}/${SAMPLE}.bam"

    # Index BAM
    samtools index -@ "${THREADS}" "${RESULTS_DIR}/${SAMPLE}.bam"

    # Call variants with lofreq
    lofreq call-parallel --pp-threads "${THREADS}" -f "${REF_PATH}" -o "${RESULTS_DIR}/${SAMPLE}.vcf" \
        "${RESULTS_DIR}/${SAMPLE}.bam"

    # Compress and index VCF
    bgzip -f "${RESULTS_DIR}/${SAMPLE}.vcf"
    tabix -p vcf "${RESULTS_DIR}/${SAMPLE}.vcf.gz"
    rm "${RESULTS_DIR}/${SAMPLE}.vcf"
done

# Collapse variants into a single TSV file
{
    echo "sample\tchrom\tpos\tref\talt\taf"
    for SAMPLE in "${SAMPLE_LIST[@]}"; do
        bcftools query -f '%SAMPLE\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' \
            "${RESULTS_DIR}/${SAMPLE}.vcf.gz" --output-type t
    done
} > "${RESULTS_DIR}/collapsed.tsv"

exit 0