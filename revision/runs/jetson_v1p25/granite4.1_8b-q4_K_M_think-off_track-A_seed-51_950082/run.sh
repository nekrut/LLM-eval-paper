#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
REF_FASTA="data/ref/chrM.fa"
RESULTS_DIR="results"

mkdir -p "${RESULTS_DIR}"

# Index reference if not present
if [[ ! -e "${REF_FASTA}.fai" ]] || \
   [[ ! -e "$(dirname "${REF_FASTA}")/.bwa_index_${REF_FASTA##*/}" ]]; then
    samtools faidx "${REF_FASTA}"
    bwa index "${REF_FASTA}"
fi

for SAMPLE in "${SAMPLES[@]}"; do
    # Skip if VCF.gz.tbi exists and is newer than BAM or reference
    if [[ -e "${RESULTS_DIR}/${SAMPLE}.vcf.gz.tbi" ]] && \
       ([[ ! -e "${RESULTS_DIR}/${SAMPLE}.bam" ]] || \
        ([[ -e "${RESULTS_DIR}/${SAMPLE}.bam" ]] && \
         [[ "$(stat -c %Y "${RESULTS_DIR}/${SAMPLE}.bam")" -le "$(stat -c %Y "${RESULTS_DIR}/${SAMPLE}.vcf.gz.tbi")" ]]) || \
        ([[ -e "${REF_FASTA}" ]] && \
         [[ "$(stat -c %Y "${REF_FASTA}")" -le "$(stat -c %Y "${RESULTS_DIR}/${SAMPLE}.vcf.gz.tbi")" ]])); then
        continue
    fi

    # Align paired-end reads
    bwa mem -t "${THREADS}" -R "@RG\tID:${SAMPLE}\tSM:${SAMPLE}\tLB:${SAMPLE}\tPL:ILLUMINA" \
        "${REF_FASTA}" "data/raw/${SAMPLE}_1.fq.gz" "data/raw/${SAMPLE}_2.fq.gz" |
    samtools sort -@ "${THREADS}" -o "${RESULTS_DIR}/${SAMPLE}.bam"

    # Index BAM
    samtools index -@ "${THREADS}" "${RESULTS_DIR}/${SAMPLE}.bam"

    # Variant calling
    lofreq call-parallel --pp-threads "${THREADS}" -f "${REF_FASTA}" -o "${RESULTS_DIR}/${SAMPLE}.vcf" \
        "${RESULTS_DIR}/${SAMPLE}.bam"

    # Compress and index VCF
    bgzip -f "${RESULTS_DIR}/${SAMPLE}.vcf"
    tabix -p vcf "${RESULTS_DIR}/${SAMPLE}.vcf.gz"
    rm "${RESULTS_DIR}/${SAMPLE}.vcf"

done

# Collapse variants into a single TSV file
{
    echo "sample\tchrom\tpos\tref\talt\taf"
    for SAMPLE in "${SAMPLES[@]}"; do
        bcftools query -f '%SAMPLE\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' \
            "${RESULTS_DIR}/${SAMPLE}.vcf.gz" >> "${RESULTS_DIR}/collapsed.tsv"
    done
} > "${RESULTS_DIR}/collapsed.tsv"

exit 0