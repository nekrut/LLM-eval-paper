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

# Index the reference genome with BWA if not already present (BWA index files: chrM.bwt, chrM.pac, chrM.ann, chrM.sa)
if [[ ! -e "${REF_DIR}/chrM.bwt" ]]; then
    bwa index "${REF_FASTA}"
fi

# Loop over each sample to perform alignment and variant calling
for SAMPLE in "${SAMPLES[@]}"; do
    # Determine FASTQ filenames for the paired-end reads of the current sample
    R1="${RAW_DIR}/${SAMPLE}_1.fq.gz"
    R2="${RAW_DIR}/${SAMPLE}_2.fq.gz"

    # Align reads to the mitochondrial reference using BWA mem
    bwa mem -t 4 "${REF_FASTA}" "${R1}" "${R2}" | \
        samtools view -bS - > "${RESULTS_DIR}/${SAMPLE}.bam"

    # Sort and index the BAM file
    samtools sort -@ 4 -o "${RESULTS_DIR}/${SAMPLE}.sorted.bam" "${RESULTS_DIR}/${SAMPLE}.bam"
    mv "${RESULTS_DIR}/${SAMPLE}.sorted.bam" "${RESULTS_DIR}/${SAMPLE}.bam"
    samtools index "${RESULTS_DIR}/${SAMPLE}.bam"

    # Call variants using Lofreq with the mitochondrial reference
    lofreq call -f "${REF_FASTA}" -o "${RESULTS_DIR}/${SAMPLE}.vcf.gz" --threads 4 "${RESULTS_DIR}/${SAMPLE}.bam"

    # Compress and index the VCF file
    bcftools view -Oz -o "${RESULTS_DIR}/${SAMPLE}.vcf.gz" "${RESULTS_DIR}/${SAMPLE}.vcf"
    bcftools index "${RESULTS_DIR}/${SAMPLE}.vcf.gz"
done

# Collapse variant calls across all samples into a single TSV file
{
    echo "sample chrom pos ref alt af"
    for SAMPLE in "${SAMPLES[@]}"; do
        # Extract relevant columns from the VCF of the current sample
        bcftools view -H "${RESULTS_DIR}/${SAMPLE}.vcf.gz" | \
            awk -v sample="${SAMPLE}" '
                /^##/ {next}
                /^[^#]/ {
                    split($1, a, ":"); chrom = a[1]
                    split($2, b, ":"); pos   = b[1]
                    ref  = $4
                    alt  = $5
                    af    = $(NF-1)
                    printf("%s\t%s\t%s\t%s\t%s\t%.6f\n", sample, chrom, pos, ref, alt, af)
                }
            '
    done | sort -u
} > "${RESULTS_DIR}/collapsed.tsv"

# Ensure idempotence: if results directory already contains all expected files, exit successfully
if [[ -e "${RESULTS_DIR}/${SAMPLES[0]}.bam" && -e "${RESULTS_DIR}/${SAMPLES[0]}.vcf.gz" && -e "${RESULTS_DIR}/collapsed.tsv" ]]; then
    exit 0
fi