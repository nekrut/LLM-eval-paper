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

# Reference indexing (idempotent)
if [[ ! -e "${REF_DIR}/chrM.fa.fai" ]] || \
   [[ ! -e "${REF_DIR}/chrM.fa.amb" ]] || \
   [[ ! -e "${REF_DIR}/chrM.fa.ann" ]] || \
   [[ ! -e "${REF_DIR}/chrM.fa.bwt" ]] || \
   [[ ! -e "${REF_DIR}/chrM.fa.pac" ]] || \
   [[ ! -e "${REF_DIR}/chrM.fa.sa" ]]; then
    samtools faidx "${REF_FASTA}"
    bwa index "${REF_FASTA}"
fi

# Process each sample
for SAMPLE in "${SAMPLE_LIST[@]}"; do
    # Alignment (idempotent)
    if [[ ! -e "${RESULTS_DIR}/${SAMPLE}.bam.bai" ]] || \
       [[ "$(stat -c %Y "${RAW_DIR}/${SAMPLE}_1.fq.gz")" -gt "$(stat -c %Y "${RESULTS_DIR}/${SAMPLE}.bai")" ]]; then
        bwa mem -t "${THREADS}" -R "@RG\tID:${SAMPLE}\tSM:${SAMPLE}\tLB:${SAMPLE}\tPL:ILLUMINA" \
            "${REF_FASTA}" "${RAW_DIR}/${SAMPLE}_1.fq.gz" "${RAW_DIR}/${SAMPLE}_2.fq.gz" |
        samtools sort -@ "${THREADS}" -o "${RESULTS_DIR}/${SAMPLE}.bam"
    fi

    # BAM indexing (idempotent)
    if [[ ! -e "${RESULTS_DIR}/${SAMPLE}.bam.bai" ]]; then
        samtools index -@ "${THREADS}" "${RESULTS_DIR}/${SAMPLE}.bam"
    fi

    # Variant calling with lofreq (idempotent)
    if [[ ! -e "${RESULTS_DIR}/${SAMPLE}.vcf.gz.tbi" ]] || \
       [[ "$(stat -c %Y "${RESULTS_DIR}/${SAMPLE}.bam.bai")" -gt "$(stat -c %Y "${RESULTS_DIR}/${SAMPLE}.vcf.gz.tbi")" ]]; then
        lofreq call-parallel --pp-threads "${THREADS}" --ref "${REF_FASTA}" \
            --out "${RESULTS_DIR}/${SAMPLE}.vcf" results/${SAMPLE}.bam
        bgzip "${RESULTS_DIR}/${SAMPLE}.vcf"
        tabix -p vcf "${RESULTS_DIR}/${SAMPLE}.vcf.gz"
        rm "${RESULTS_DIR}/${SAMPLE}.vcf"
    fi
done

# Collapse step to produce collapsed.tsv (idempotent)
if [[ ! -e "results/collapsed.tsv" ]] || \
   any_new_vcf=$(find "${RESULTS_DIR}" -name "*.vcf.gz" | while read VCF; do
       sample=$(basename "${VCF%.vcf.gz}")
       if [[ "$(stat -c %Y "${RAW_DIR}/${sample}_1.fq.gz")" -gt "$(stat -c %y "${VCF}.tbi")" ]]; then
           echo 1
           break
       fi
   done); [[ ${any_new_vcf} == "1" ]] ; then
    cat <<EOF > results/collapsed.tsv
sample	chrom	pos	ref	alt	af
EOF
    for SAMPLE in "${SAMPLE_LIST[@]}"; do
        bcftools query -f '${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' \
            "${RESULTS_DIR}/${SAMPLE}.vcf.gz" >> results/collapsed.tsv
    done
fi

exit 0