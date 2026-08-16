#!/usr/bin/env bash
set -euo pipefail

# Define input and output directories relative to current working directory
RAW_DIR="data/raw"
REF_DIR="data/ref"
RESULTS_DIR="results"

# Ensure results directory exists
mkdir -p "${RESULTS_DIR}"

# Reference genome file (already decompressed)
REF_FASTA="${REF_DIR}/chrM.fa"

# List of sample names derived from FASTQ filenames
declare -a SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

# Loop over each sample to perform alignment and variant calling
for SAMPLE in "${SAMPLES[@]}"; do
    # Paired-end FASTQ files for the current sample
    R1="${RAW_DIR}/${SAMPLE}_1.fq.gz"
    R2="${RAW_DIR}/${SAMPLE}_2.fq.gz"

    # Align reads to mitochondrial reference using BWA MEM
    bwa mem "${REF_FASTA}" "${R1}" "${R2}" | \
        samtools view -bS - > "${RESULTS_DIR}/${SAMPLE}.bam"

    # Sort and index the BAM file
    samtools sort -o "${RESULTS_DIR}/${SAMPLE}.sorted.bam" "${RESULTS_DIR}/${SAMPLE}.bam"
    mv "${RESULTS_DIR}/${SAMPLE}.sorted.bam" "${RESULTS_DIR}/${SAMPLE}.bam"
    samtools index "${RESULTS_DIR}/${SAMPLE}.bam"

    # Call variants using Lofreq with the mitochondrial reference
    lofreq call -f "${REF_FASTA}" --bam "${RESULTS_DIR}/${SAMPLE}.bam" \
        --threads 4 | \
        bcftools view -Oz > "${RESULTS_DIR}/${SAMPLE}.vcf.gz"
    
    # Compress and index the VCF file
    bcftools index "${RESULTS_DIR}/${SAMPLE}.vcf.gz"

    # Extract AF information for each variant in a tab-separated format
    bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\tAF\n' "${RESULTS_DIR}/${SAMPLE}.vcf.gz" > \
        "${RESULTS_DIR}/${SAMPLE}_variants.tsv"
done

# Collapse the per-sample variant tables into a single table (collapsed.tsv)
{
    echo "sample chrom pos ref alt af"
    for SAMPLE in "${SAMPLES[@]}"; do
        cat "${RESULTS_DIR}/${SAMPLE}_variants.tsv" | \
            awk -v sample="${SAMPLE}" 'NR>1 {print sample, $1, $2, $3, $4, $5}'
    done
} > "${RESULTS_DIR}/collapsed.tsv"

# Make the script idempotent: if results/ directory already contains all expected files,
# exit successfully without redoing any work.
if [[ -e "${RESULTS_DIR}/${SAMPLES[0]}.bam" && -e "${RESULTS_DIR}/collapsed.tsv" ]]; then
    exit 0
fi