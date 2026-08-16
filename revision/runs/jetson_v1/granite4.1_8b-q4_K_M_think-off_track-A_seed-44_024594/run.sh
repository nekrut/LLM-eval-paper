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
    # Skip if VCF and its index are up-to-date
    if [[ -f "${RESULTS_DIR}/${SAMPLE}.vcf.gz.tbi" ]] && \
       [[ "$(stat -c %Y "${RESULTS_DIR}/${SAMPLE}.vcf.gz")" -ge "$(stat -c %Y "${REF_FASTA}")" ]]; then
        continue
    fi

    # Align reads with BWA MEM
    bwa mem -t "${THREADS}" -R "@RG\tID:${SAMPLE}\tSM:${SAMPLE}\tLB:${SAMPLE}\tPL:ILLUMINA" \
             "data/raw/${SAMPLE}_1.fq.gz" "data/raw/${SAMPLE}_2.fq.gz" |
        samtools sort -@ "${THREADS}" -o "${RESULTS_DIR}/${SAMPLE}.bam"

    # Index BAM
    samtools index -@ "${THREADS}" "${RESULTS_DIR}/${SAMPLE}.bam"

    # Call variants with LOFREQ
    TEMP_VCF="${RESULTS_DIR}/${SAMPLE}.vcf"
    lofreq call-parallel --pp-threads "${THREADS}" \
                          -O v -o "${TEMP_VCF}" \
                          -R "${REF_FASTA}" \
                          "${RESULTS_DIR}/${SAMPLE}.bam"

    # Compress and index VCF
    bgzip -c "${TEMP_VCF}" > "${RESULTS_DIR}/${SAMPLE}.vcf.gz"
    tabix -p vcf "${RESULTS_DIR}/${SAMPLE}.vcf.gz"
    rm "${TEMP_VCF}"

    # Touch the .tbi file if missing (tabix creates it automatically, but ensure directory exists)
    [[ -d "$(dirname "${RESULTS_DIR}/${SAMPLE}.vcf.gz.tbi")" ]] || mkdir -p "$(dirname "${RESULTS_DIR}/${SAMPLE}.vcf.gz.tbi")"
done

# Collapse variants into a single TSV
{
    echo "sample\tchrom\tpos\tref\talt\taf"
    for SAMPLE in "${SAMPLE_LIST[@]}"; do
        bcftools query -f '%SAMPLE\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' \
                       "${RESULTS_DIR}/${SAMPLE}.vcf.gz" >> "${RESULTS_DIR}/collapsed.tsv"
    done
} > "${RESULTS_DIR}/collapsed.tsv"

exit 0