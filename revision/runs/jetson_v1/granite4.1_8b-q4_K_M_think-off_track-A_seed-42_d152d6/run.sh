#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
REF="data/ref/chrM.fa"
RESULTS_DIR="results"

mkdir -p "${RESULTS_DIR}"

# Ensure reference index exists
if [[ ! -e "${REF}.fai" ]] || \
   [[ ! -e "$(dirname "${REF}")/.bwa_index_${REF##*/}" ]]; then
    samtools faidx "${REF}"
    bwa index "${REF}"
fi

for SAMPLE in "${SAMPLES[@]}"; do
    # Skip if VCF and its index already exist and are up-to-date
    if [[ -e "${RESULTS_DIR}/${SAMPLE}.vcf.gz" && \
          -e "${RESULTS_DIR}/${SAMPLE}.vcf.gz.tbi" ]]; then
        continue
    fi

    R1="data/raw/${SAMPLE}_1.fq.gz"
    R2="data/raw/${SAMPLE}_2.fq.gz"

    # Align reads with bwa mem
    bwa mem -t "${THREADS}" \
        -R "@RG\tID:${SAMPLE}\tSM:${SAMPLE}\tLB:${SAMPLE}\tPL:ILLUMINA" \
        "${REF}" "${R1}" "${R2}" | \
    samtools sort -@ "${THREADS}" -o "${RESULTS_DIR}/${SAMPLE}.bam"

    # Index BAM
    samtools index -@ "${THREADS}" "${RESULTS_DIR}/${SAMPLE}.bam"

    # Call variants with lofreq
    TEMP_VCF="${RESULTS_DIR}/${SAMPLE}.vcf"
    lofreq call-parallel --pp-threads "${THREADS}" \
        --ref "${REF}" \
        --in "${RESULTS_DIR}/${SAMPLE}.bam" \
        -o "${TEMP_VCF}"

    # Compress and index VCF
    bgzip -c "${TEMP_VCF}" > "${RESULTS_DIR}/${SAMPLE}.vcf.gz"
    tabix -p vcf "${RESULTS_DIR}/${SAMPLE}.vcf.gz"
    rm "${TEMP_VCF}"
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