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
       [[ "$(stat -c %Y "${RESULTS_DIR}/${SAMPLE}.vcf.gz")" -ge "$(stat -c %Y "${RESULTS_DIR}/${SAMPLE}.bam")" ]]; then
        continue
    fi

    # Align reads with BWA mem
    bwa mem -t "${THREADS}" \
        -R "@RG\tID:${SAMPLE}\tSM:${SAMPLE}\tLB:${SAMPLE}\tPL:ILLUMINA" \
        "${REF_FASTA}" \
        "data/raw/${SAMPLE}_1.fq.gz" \
        "data/raw/${SAMPLE}_2.fq.gz" |
    samtools sort -@ "${THREADS}" -o "${RESULTS_DIR}/${SAMPLE}.bam"

    # Index BAM
    samtools index -@ "${THREADS}" "${RESULTS_DIR}/${SAMPLE}.bam"

    # Variant calling with lofreq call-parallel
    tmp_vcf="${RESULTS_DIR}/${SAMPLE}.vcf"
    lofreq call-parallel --pp-threads "${THREADS}" \
        --ref "${REF_FASTA}" \
        "${RESULTS_DIR}/${SAMPLE}.bam" > "${tmp_vcf}"

    # Compress and index VCF
    bgzip -c "${tmp_vcf}" > "${RESULTS_DIR}/${SAMPLE}.vcf.gz"
    tabix -p vcf "${RESULTS_DIR}/${SAMPLE}.vcf.gz"
    rm "${tmp_vcf}"
done

# Collapse variants into a single TSV file
echo "sample\tchrom\tpos\tref\talt\taf" > "${RESULTS_DIR}/collapsed.tsv"
for SAMPLE in "${SAMPLE_LIST[@]}"; do
    bcftools query -f '%SAMPLE\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' \
        "${RESULTS_DIR}/${SAMPLE}.vcf.gz" >> "${RESULTS_DIR}/collapsed.tsv"
done

exit 0