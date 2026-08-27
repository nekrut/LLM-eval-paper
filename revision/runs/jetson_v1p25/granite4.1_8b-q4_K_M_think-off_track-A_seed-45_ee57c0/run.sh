#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
REF="data/ref/chrM.fa"
RESULTS_DIR="results"

mkdir -p "${RESULTS_DIR}"

# Index reference if not present
if [[ ! -e "${REF}.fai" ]] || \
   [[ ! -e "$(dirname "${REF}")/.bwa_index_${REF##*/}" ]]; then
    samtools faidx "${REF}"
    bwa index "${REF}"
fi

for SAMPLE in "${SAMPLES[@]}"; do
    # Skip if VCF and its index are up-to-date
    if [[ -e "${RESULTS_DIR}/${SAMPLE}.vcf.gz.tbi" ]] && \
       [[ "${RESULTS_DIR}/${SAMPLE}.vcf.gz.tbi" -nt "${REF}" ]]; then
        continue
    fi

    # Align reads
    bwa mem -t "${THREADS}" -R "@RG\tID:${SAMPLE}\tSM:${SAMPLE}\tLB:${SAMPLE}\tPL:ILLUMINA" \
        "data/raw/${SAMPLE}_1.fq.gz" "data/raw/${SAMPLE}_2.fq.gz" \
        | samtools sort -@ "${THREADS}" -o "${RESULTS_DIR}/${SAMPLE}.bam"

    # Index BAM
    samtools index -@ "${THREADS}" "${RESULTS_DIR}/${SAMPLE}.bam"

    # Call variants
    lofreq call-parallel --pp-threads "${THREADS}" -f "${REF}" -o "${RESULTS_DIR}/${SAMPLE}.vcf" \
        "${RESULTS_DIR}/${SAMPLE}.bam"

    # Compress and index VCF
    bgzip -f "${RESULTS_DIR}/${SAMPLE}.vcf"
    tabix -p vcf "${RESULTS_DIR}/${SAMPLE}.vcf.gz"
    rm "${RESULTS_DIR}/${SAMPLE}.vcf"

    # Ensure the TSV is up-to-date
    if [[ ! -e "${RESULTS_DIR}/collapsed.tsv" ]] || \
       [[ "${RESULTS_DIR}/collapsed.tsv" -ot "${RESULTS_DIR}/${SAMPLE}.vcf.gz" ]]; then
        bcftools query -f '${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "${RESULTS_DIR}/${SAMPLE}.vcf.gz"
    fi
done

# Create collapsed TSV if not present or outdated
if [[ ! -e "${RESULTS_DIR}/collapsed.tsv" ]] || \
   [[ "${RESULTS_DIR}/collapsed.tsv" -ot "$(find "${RESULTS_DIR}" -name '*.vcf.gz' -printf '%T@ %p\n' | sort -nr | head -n1)" ]]; then
    echo "sample\tchrom\tpos\tref\talt\taf" > "${RESULTS_DIR}/collapsed.tsv"
    for SAMPLE in "${SAMPLES[@]}"; do
        bcftools query -f '${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "${RESULTS_DIR}/${SAMPLE}.vcf.gz" >> "${RESULTS_DIR}/collapsed.tsv"
    done
fi

exit 0