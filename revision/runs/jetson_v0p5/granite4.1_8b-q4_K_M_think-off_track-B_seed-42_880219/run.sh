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

# List of sample identifiers
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

# Loop over each sample to perform alignment and variant calling
for SAMPLE in "${SAMPLES[@]}"; do
    # Paired-end FASTQ files for the current sample
    R1="${RAW_DIR}/${SAMPLE}_1.fq.gz"
    R2="${RAW_DIR}/${SAMPLE}_2.fq.gz"

    # Align reads using BWA mem
    bwa mem -t 4 "${REF_FASTA}" "${R1}" "${R2}" | \
        samtools view -bS - > "${RESULTS_DIR}/${SAMPLE}.bam"

    # Index the BAM file
    samtools sort -@ 4 -o "${RESULTS_DIR}/${SAMPLE}.sorted.bam" "${RESULTS_DIR}/${SAMPLE}.bam"
    mv "${RESULTS_DIR}/${SAMPLE}.sorted.bam" "${RESULTS_DIR}/${SAMPLE}.bam"
    samtools index -@ 4 "${RESULTS_DIR}/${SAMPLE}.bam"

    # Call variants using Lofreq
    lofreq call -f "${REF_FASTA}" -o "${RESULTS_DIR}/${SAMPLE}.vcf.gz" \
        --threads 4 "${RESULTS_DIR}/${SAMPLE}.bam"

    # Compress and index the VCF file
    bcftools view -Oz -o "${RESULTS_DIR}/${SAMPLE}.vcf.gz" "${RESULTS_DIR}/${SAMPLE}.vcf"
    tabix -p vcf "${RESULTS_DIR}/${SAMPLE}.vcf.gz"
done

# Collapse variants across samples into a single TSV file
{
    echo "sample chrom pos ref alt af"
    for SAMPLE in "${SAMPLES[@]}"; do
        bcftools view -H "${RESULTS_DIR}/${SAMPLE}.vcf.gz" | \
            awk -v sample="${SAMPLE}" '
                NR == 1 { header = $0; next }
                {
                    split($4, a, "/"); ref = a[1]; alt = a[2];
                    pos = $3; chrom = $1;
                    af = (split($8, b, ":") > 0) ? b[2] : "";
                    printf("%s\t%s\t%d\t%s\t%s\t%.6f\n", sample, chrom, pos, ref, alt, af);
                }
            '
    done
} > "${RESULTS_DIR}/collapsed.tsv"

# Make the script idempotent: if results/ directory already contains all expected files, exit successfully
if [ -e "${RESULTS_DIR}/${SAMPLES[0]}.bam" ] && \
   [ -e "${RESULTS_DIR}/${SAMPLES[0]}.bam.bai" ] && \
   [ -e "${RESULTS_DIR}/${SAMPLES[0]}.vcf.gz" ] && \
   [ -e "${RESULTS_DIR}/${SAMPLES[0]}.vcf.gz.tbi" ] && \
   [ -e "${RESULTS_DIR}/collapsed.tsv" ]; then
    exit 0
fi