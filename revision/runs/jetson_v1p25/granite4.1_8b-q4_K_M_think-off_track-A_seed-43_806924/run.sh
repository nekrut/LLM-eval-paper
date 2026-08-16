#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLE_LIST=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
REF_FASTA="data/ref/chrM.fa"
RESULTS_DIR="results"

mkdir -p "${RESULTS_DIR}"

# Ensure reference index exists
if [[ ! -f "${REF_FASTA}.fai" ]] || \
   [[ ! -f "$(dirname "${REF_FASTA}")/$(basename "${REF_FASTA}" .fa).amb" ]]; then
    samtools faidx "${REF_FASTA}"
    bwa index "${REF_FASTA}"
fi

for SAMPLE in "${SAMPLE_LIST[@]}"; do
    # Skip if output already exists and is up-to-date
    if [[ -e "${RESULTS_DIR}/${SAMPLE}.vcf.gz.tbi" ]] && \
       [[ "${RESULTS_DIR}/${SAMPLE}.vcf.gz.tbi" -nt "data/raw/${SAMPLE}_1.fq.gz" ]]; then
        continue
    fi

    # Align reads with bwa mem
    bwa mem -t "${THREADS}" -R "@RG\tID:${SAMPLE}\tSM:${SAMPLE}\tLB:${SAMPLE}\tPL:ILLUMINA" \
             "data/raw/${SAMPLE}_1.fq.gz" "data/raw/${SAMPLE}_2.fq.gz" |
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

done

# Collapse variants into a single TSV file
{
    echo "sample\tchrom\tpos\tref\talt\taf"
    for SAMPLE in "${SAMPLE_LIST[@]}"; do
        bcftools query -f '%SAMPLE\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' \
                       "${RESULTS_DIR}/${SAMPLE}.vcf.gz" || true
    done
} > "${RESULTS_DIR}/collapsed.tsv"

exit 0