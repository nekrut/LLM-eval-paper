#!/usr/bin/env bash
set -euo pipefail

# Define input and output directories relative to current working directory
RAW_DIR="data/raw"
REF_DIR="data/ref"
RESULTS_DIR="results"

# Ensure results directory exists
mkdir -p "${RESULTS_DIR}"

# Reference genome file (already decompressed)
REF_FA="${REF_DIR}/chrM.fa"

# List of sample names derived from FASTQ filenames
declare -a SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

# Loop over each sample to perform alignment and variant calling
for SAMPLE in "${SAMPLES[@]}"; do
    # Determine paired-end FASTQ files for the current sample
    PAIRED_FQ_1="${RAW_DIR}/${SAMPLE}_1.fq.gz"
    PAIRED_FQ_2="${RAW_DIR}/${SAMPLE}_2.fq.gz"

    # Align reads to mitochondrial reference using BWA mem
    bwa mem "${REF_FA}" "${PAIRED_FQ_1}" "${PAIRED_FQ_2}" | \
        samtools view -bS - > "${RESULTS_DIR}/${SAMPLE}.bam"

    # Index the BAM file
    samtools sort -@ 4 -o "${RESULTS_DIR}/${SAMPLE}.sorted.bam" "${RESULTS_DIR}/${SAMPLE}.bam"
    mv "${RESULTS_DIR}/${SAMPLE}.sorted.bam" "${RESULTS_DIR}/${SAMPLE}.bam"
    samtools index "${RESULTS_DIR}/${SAMPLE}.bam"

    # Call variants using Lofreq
    lofreq call --bam "${RESULTS_DIR}/${SAMPLE}.bam" \
                --ref "${REF_FA}" \
                -o "${RESULTS_DIR}/${SAMPLE}.vcf.gz" \
                --threads 4

    # Compress and index the VCF file
    bcftools view "${RESULTS_DIR}/${SAMPLE}.vcf.gz" | \
        bcftools sort -o "${RESULTS_DIR}/${SAMPLE}.sorted.vcf.gz"
    mv "${RESULTS_DIR}/${SAMPLE}.sorted.vcf.gz" "${RESULTS_DIR}/${SAMPLE}.vcf.gz"
    bcftools index "${RESULTS_DIR}/${SAMPLE}.vcf.gz"

    # Extract AF information for collapsed table
    bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\tAF\n' "${RESULTS_DIR}/${SAMPLE}.vcf.gz" > \
        "${RESULTS_DIR}/${SAMPLE}_af.tsv"
done

# Collapse the per-sample AF tables into a single TSV file
cat "${RESULTS_DIR}"/*.af.tsv | sort -u > "${RESULTS_DIR}/collapsed.tsv"

# Clean up intermediate AF files
rm "${RESULTS_DIR}"/*.af.tsv

exit 0