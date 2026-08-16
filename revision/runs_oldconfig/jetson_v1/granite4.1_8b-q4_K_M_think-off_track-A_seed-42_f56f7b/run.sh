#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLE_LIST=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
REF_PATH="data/ref/chrM.fa"
RESULTS_DIR="results"

mkdir -p "${RESULTS_DIR}"

# Ensure reference index exists
if [[ ! -f "${REF_PATH}.fai" ]] || \
   [[ ! -f "$(dirname "${REF_PATH}")/$(basename "${REF_PATH}" .fa).amb" ]]; then
    samtools faidx "${REF_PATH}"
    bwa index "${REF_PATH}"
fi

for SAMPLE in "${SAMPLE_LIST[@]}"; do
    # Skip if VCF and its index already exist and are up-to-date
    if [[ -f "${RESULTS_DIR}/${SAMPLE}.vcf.gz" ]] && \
       [[ -f "${RESULTS_DIR}/${SAMPLE}.vcf.gz.tbi" ]]; then
        continue
    fi

    # Align reads with bwa mem
    bwa mem -t "${THREADS}" -R "@RG\tID:${SAMPLE}\tSM:${SAMPLE}\tLB:${SAMPLE}\tPL:ILLUMINA" \
             "data/raw/${SAMPLE}_1.fq.gz" "data/raw/${SAMPLE}_2.fq.gz" |
        samtools sort -@ "${THREADS}" -o "${RESULTS_DIR}/${SAMPLE}.bam"

    # Index BAM
    samtools index -@ "${THREADS}" "${RESULTS_DIR}/${SAMPLE}.bam"

    # Call variants with lofreq
    TEMP_VCF="${RESULTS_DIR}/${SAMPLE}.vcf"
    lofreq call-parallel --pp-threads "${THREADS}" \
        -o "${TEMP_VCF}" \
        -R "@RG\tID:${SAMPLE}\tSM:${SAMPLE}\tLB:${SAMPLE}\tPL:ILLUMINA" \
        "${REF_PATH}" "${RESULTS_DIR}/${SAMPLE}.bam"

    # Compress and index VCF
    bgzip -f "${TEMP_VCF}"
    tabix -p vcf "${RESULTS_DIR}/${SAMPLE}.vcf.gz"
    rm "${TEMP_VCF}"

    # Record variant info for collapsing later
    bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' \
        "${RESULTS_DIR}/${SAMPLE}.vcf.gz" > \
        "${RESULTS_DIR}/tmp_${SAMPLE}_info.tsv"
done

# Collapse all sample outputs into a single TSV
{
    echo "sample	chrom	pos	ref	alt	af"
    for SAMPLE in "${SAMPLE_LIST[@]}"; do
        cat "${RESULTS_DIR}/tmp_${SAMPLE}_info.tsv" | \
            awk -v samp="${SAMPLE}" '{print samp "\t" $1 "\t" $2 "\t" $3 "\t" $4 "\t" $5}'
    done
} > "${RESULTS_DIR}/collapsed.tsv"

# Clean up temporary files
rm "${RESULTS_DIR:?}/tmp_*_info.tsv"

exit 0