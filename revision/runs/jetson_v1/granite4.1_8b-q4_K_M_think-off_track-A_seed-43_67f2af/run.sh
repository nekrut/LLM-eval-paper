#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLE_LIST=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
REF_FASTA="data/ref/chrM.fa"
RESULTS_DIR="results"

mkdir -p "${RESULTS_DIR}"

# Ensure reference index files exist
if [[ ! -f "${REF_FASTA}.fai" ]] || \
   [[ ! -f "$(dirname "${REF_FASTA}")/$(basename "${REF_FASTA}" .fa).amb" ]]; then
    samtools faidx "${REF_FASTA}"
    bwa index "${REF_FASTA}"
fi

for SAMPLE in "${SAMPLE_LIST[@]}"; do
    # Skip if VCF and its index are up-to-date
    if [[ -f "${RESULTS_DIR}/${SAMPLE}.vcf.gz.tbi" ]] && \
       [[ "${RESULTS_DIR}/${SAMPLE}.vcf.gz.tbi" -nt "${REF_FASTA}" ]]; then
        continue
    fi

    # Align reads with bwa mem
    bwa mem -t "${THREADS}" \
        -R "@RG\tID:${SAMPLE}\tSM:${SAMPLE}\tLB:${SAMPLE}\tPL:ILLUMINA" \
        "${REF_FASTA}" \
        "data/raw/${SAMPLE}_1.fq.gz" \
        "data/raw/${SAMPLE}_2.fq.gz" |
    samtools sort -@ "${THREADS}" -o "${RESULTS_DIR}/${SAMPLE}.bam"

    # Index BAM
    samtools index -@ "${THREADS}" "${RESULTS_DIR}/${SAMPLE}.bam"

    # Variant calling with lofreq
    lofreq call-parallel --pp-threads "${THREADS}" \
        --ref "${REF_FASTA}" \
        "${RESULTS_DIR}/${SAMPLE}.bam" |
    bgzip -c > "${RESULTS_DIR}/${SAMPLE}.vcf.gz"
    
    tabix -p vcf "${RESULTS_DIR}/${SAMPLE}.vcf.gz"

    # Clean intermediate VCF
    rm "${RESULTS_DIR}/${SAMPLE}.vcf"
done

# Collapse variants into a single TSV file
{
    echo "sample\tchrom\tpos\tref\talt\taf"
    for SAMPLE in "${SAMPLE_LIST[@]}"; do
        bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' \
            "${RESULTS_DIR}/${SAMPLE}.vcf.gz" |
        sed "1s/^/${SAMPLE}\t/"   # prepend sample name to each line
    done
} > "${RESULTS_DIR}/collapsed.tsv"

exit 0