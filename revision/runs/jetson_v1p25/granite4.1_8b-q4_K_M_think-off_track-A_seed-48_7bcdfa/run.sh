#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLE_LIST=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
REF_FA="data/ref/chrM.fa"
RESULTS_DIR="results"

mkdir -p "${RESULTS_DIR}"

# Ensure reference index exists
if [[ ! -f "${REF_FA}.fai" ]] || \
   [[ ! -f "$(dirname "${REF_FA}")/$(basename "${REF_FA}" .fa).amb" ]]; then
    samtools faidx "${REF_FA}"
    bwa index "${REF_FA}"
fi

for SAMPLE in "${SAMPLE_LIST[@]}"; do
    # Skip if VCF and its index already exist and are up-to-date
    if [[ -f "${RESULTS_DIR}/${SAMPLE}.vcf.gz.tbi" ]] && \
       [[ "${RESULTS_DIR}/${SAMPLE}.vcf.gz.tbi" -nt "${REF_FA}" ]]; then
        continue
    fi

    # Align reads with bwa mem
    RGPL="ILLUMINA"
    PL="ILLUMINA"
    LB="${SAMPLE}"
    RG="@RG\\tID:${SAMPLE}\\tSM:${SAMPLE}\\tLB:${LB}\\tPL:${PL}"
    bwa mem -t "${THREADS}" -R "${RG}" \
        "data/raw/${SAMPLE}_1.fq.gz" \
        "data/raw/${SAMPLE}_2.fq.gz" \
        | samtools sort -@ "${THREADS}" -o "${RESULTS_DIR}/${SAMPLE}.bam"

    # Index BAM
    samtools index -@ "${THREADS}" "${RESULTS_DIR}/${SAMPLE}.bam"

    # Call variants with lofreq
    lofreq call-parallel --pp-threads "${THREADS}" \
        -f "${REF_FA}" -o "${RESULTS_DIR}/${SAMPLE}.vcf" \
        "${RESULTS_DIR}/${SAMPLE}.bam"

    # Compress and index VCF
    bgzip -f "${RESULTS_DIR}/${SAMPLE}.vcf"
    tabix -p vcf "${RESULTS_DIR}/${SAMPLE}.vcf.gz"
    rm "${RESULTS_DIR}/${SAMPLE}.vcf"

    # Add sample name to each line of the VCF for later collapse
    bcftools rehead -s "${SAMPLE} " "${RESULTS_DIR}/${SAMPLE}.vcf.gz" > "${RESULTS_DIR}/${SAMPLE}_named.vcf.gz"
    mv "${RESULTS_DIR}/${SAMPLE}_named.vcf.gz" "${RESULTS_DIR}/${SAMPLE}.vcf.gz"
done

# Collapse all per-sample VCFs into a single table
{
    echo "sample\tchrom\tpos\tref\talt\taf"
    for SAMPLE in "${SAMPLE_LIST[@]}"; do
        bcftools query -f '%SAMPLE\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' \
            "${RESULTS_DIR}/${SAMPLE}.vcf.gz" || true
    done
} > "${RESULTS_DIR}/collapsed.tsv"

exit 0