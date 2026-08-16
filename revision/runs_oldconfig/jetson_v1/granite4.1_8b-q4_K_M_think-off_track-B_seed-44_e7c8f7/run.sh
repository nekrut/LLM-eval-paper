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
    # Determine paired-end FASTQ files for the current sample
    R1="${RAW_DIR}/${SAMPLE}_1.fq.gz"
    R2="${RAW_DIR}/${SAMPLE}_2.fq.gz"

    # Align reads using BWA mem (mitochondrial reference)
    bwa mem "${REF_FASTA}" "${R1}" "${R2}" > "${RESULTS_DIR}/${SAMPLE}.sam"

    # Convert SAM to sorted BAM and index
    samtools view -bS "${RESULTS_DIR}/${SAMPLE}.sam" | \
        samtools sort -o "${RESULTS_DIR}/${SAMPLE}.bam"
    samtools index "${RESULTS_DIR}/${SAMPLE}.bam"

    # Call variants using Lofreq (mitochondrial reference)
    lofreq call --ref "${REF_FASTA}" -o "${RESULTS_DIR}/${SAMPLE}.vcf.gz" \
        "${RESULTS_DIR}/${SAMPLE}.bam"

    # Compress and index VCF
    bcftools view "${RESULTS_DIR}/${SAMPLE}.vcf.gz" | \
        bcftools sort -o "${RESULTS_DIR}/${SAMPLE}.sorted.vcf.gz"
    bcftools index "${RESULTS_DIR}/${SAMPLE}.sorted.vcf.gz"

    # Rename sorted VCF to original name (optional, keep sorted for consistency)
    mv "${RESULTS_DIR}/${SAMPLE}.sorted.vcf.gz" "${RESULTS_DIR}/${SAMPLE}.vcf.gz"
    mv "${RESULTS_DIR}/${SAMPLE}.sorted.vcf.gz.tbi" "${RESULTS_DIR}/${SAMPLE}.vcf.gz.tbi"

done

# Collapse variants across samples into a single TSV file
{
    echo "sample chrom pos ref alt af"
    for SAMPLE in "${SAMPLES[@]}"; do
        bcftools view -H "${RESULTS_DIR}/${SAMPLE}.vcf.gz" | \
            awk -v sample="${SAMPLE}" '
                NR > 1 {
                    split($4, a, "/");
                    ref = a[1];
                    alt = a[length(a)];
                    af = $7;
                    print sample "\t" $2 "\t" $3 "\t" ref "\t" alt "\t" af
                }
            '
    done | sort -u
} > "${RESULTS_DIR}/collapsed.tsv"

exit 0