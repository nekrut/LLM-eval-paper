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

# List of sample pairs for paired-end reads
SAMPLE_PAIRS=(
    "M117-bl"   # forward: M117-bl_1.fq.gz, reverse: M117-bl_2.fq.gz
    "M117-ch"   # forward: M117-ch_1.fq.gz, reverse: M117-ch_2.fq.gz
    "M117C1-bl" # forward: M117C1-bl_1.fq.gz, reverse: M117C1-bl_2.fq.gz
    "M117C1-ch" # forward: M117C1-ch_1.fq.gz, reverse: M117C1-ch_2.fq.gz
)

# Index the reference genome for BWA (if not already done)
bwa index "${REF_FASTA}"

# Loop over each sample pair to perform alignment and variant calling
for SAMPLE in "${SAMPLE_PAIRS[@]}"; do
    # Forward and reverse FASTQ files
    FORWARD="${RAW_DIR}/${SAMPLE}_1.fq.gz"
    REVERSE="${RAW_DIR}/${SAMPLE}_2.fq.gz"

    # Align reads using BWA mem (paired-end)
    bwa mem -t 4 "${REF_FASTA}" "${FORWARD}" "${REVERSE}" | \
        samtools view -bS - > "${RESULTS_DIR}/${SAMPLE}.bam"

    # Sort and index the BAM file
    samtools sort -@ 4 -o "${RESULTS_DIR}/${SAMPLE}.sorted.bam" "${RESULTS_DIR}/${SAMPLE}.bam"
    mv "${RESULTS_DIR}/${SAMPLE}.sorted.bam" "${RESULTS_DIR}/${SAMPLE}.bam"
    samtools index -@ 4 "${RESULTS_DIR}/${SAMPLE}.bam"

    # Call variants using Lofreq (parallel mode)
    lofreq call --threads 4 \
        --in-bam "${RESULTS_DIR}/${SAMPLE}.bam" \
        --ref "${REF_FASTA}" \
        --out-vcf "${RESULTS_DIR}/${SAMPLE}.vcf.gz" \
        --compress-vcf

    # Compress and index the VCF file
    bcftools view -Oz -o "${RESULTS_DIR}/${SAMPLE}.vcf.gz" "${RESULTS_DIR}/${SAMPLE}.vcf"
    tabix -p vcf "${RESULTS_DIR}/${SAMPLE}.vcf.gz"

    # Convert VCF to a collapsed table (sample, chrom, pos, ref, alt, af)
    bcftools query -f '%CHROM\t%POS\t%REF\t%ALT[0]\tAF\n' "${RESULTS_DIR}/${SAMPLE}.vcf.gz" > \
        "${RESULTS_DIR}/${SAMPLE}_collapsed.tsv"
done

# Collapse all per-sample tables into a single table
if [ ! -e "${RESULTS_DIR}/collapsed.tsv" ]; then
    cat "${RESULTS_DIR}"/*.tsv | sort -u > "${RESULTS_DIR}/collapsed.tsv"
fi

exit 0