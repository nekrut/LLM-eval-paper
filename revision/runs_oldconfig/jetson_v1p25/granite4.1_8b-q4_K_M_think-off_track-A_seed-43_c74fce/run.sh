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

for SAMPLE in "${SAMPLE_LIST[@]}"; do
    # Skip if VCF and its index are up-to-date
    if [[ -f "${RESULTS_DIR}/${SAMPLE}.vcf.gz.tbi" ]] && \
       [[ "${RESULTS_DIR}/${SAMPLE}.vcf.gz.tbi" -nt "${RAW_DIR}/${SAMPLE}_1.fq.gz" ]]; then
        continue
    fi

    # Align reads with bwa mem
    bwa mem -t "${THREADS}" -R "@RG\tID:${SAMPLE}\tSM:${SAMPLE}\tLB:${SAMPLE}\tPL:ILLUMINA" \
        "${REF_FASTA}" "${RAW_DIR}/${SAMPLE}_1.fq.gz" "${RAW_DIR}/${SAMPLE}_2.fq.gz" |
    samtools sort -@ "${THREADS}" -o "${RESULTS_DIR}/${SAMPLE}.bam"

    # Index BAM
    samtools index -@ "${THREADS}" "${RESULTS_DIR}/${SAMPLE}.bam"

    # Call variants with lofreq
    lofreq call-parallel --pp-threads "${THREADS}" -f "${REF_FASTA}" -o "${RESULTS_DIR}/${SAMPLE}.vcf" \
        "${RESULTS_DIR}/${SAMPLE}.bam"

    # Compress and index VCF
    bgzip -f "${RESULTS_DIR}/${SAMPLE}.vcf"
    tabix -p vcf "${RESULTS_DIR}/${SAMPLE}.vcf.gz"
    rm "${RESULTS_DIR}/${SAMPLE}.vcf"

    # Append sample name to each line for later collapsing
    bcftools query -f 'sample\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' \
        "${RESULTS_DIR}/${SAMPLE}.vcf.gz" >> "${RESULTS_DIR}/collapsed.tsv.tmp"
done

# Add header and rename temporary file to final collapsed table
{
    echo "sample	chrom	pos	ref	alt	af"
    cat "${RESULTS_DIR}/collapsed.tsv.tmp"
} > "${RESULTS_DIR}/collapsed.tsv"

rm "${RESULTS_DIR}/collapsed.tsv.tmp"

exit 0