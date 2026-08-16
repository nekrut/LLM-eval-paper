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

# List of sample pairs for paired-end reads
SAMPLE_PAIRS=(
    "M117-bl"   # forward: M117-bl_1.fq.gz, reverse: M117-bl_2.fq.gz
    "M117-ch"
    "M117C1-bl"
    "M117C1-ch"
)

# Index the mitochondrial reference genome for BWA
bwa index "${REF_FA}"

# Loop over each sample pair to perform alignment and variant calling
for SAMPLE in "${SAMPLES[@]}"; do
    # Forward read file
    FORWARD="${RAW_DIR}/${SAMPLE}_1.fq.gz"
    # Reverse read file
    REVERSE="${RAW_DIR}/${SAMPLE}_2.fq.gz"

    # Align reads using BWA mem (paired-end)
    bwa mem -t 4 "${REF_FA}" "${FORWARD}" "${REVERSE}" | \
        samtools view -bS - > "${RESULTS_DIR}/${SAMPLE}.bam"

    # Sort the BAM file
    samtools sort -@ 4 -o "${RESULTS_DIR}/${SAMPLE}.bam" "${RESULTS_DIR}/${SAMPLE}.bam"

    # Index the sorted BAM file
    samtools index "${RESULTS_DIR}/${SAMPLE}.bam"

    # Call variants using Lofreq (parallel mode)
    lofreq call --threads 4 \
        -f "${REF_FA}" \
        -i "${RESULTS_DIR}/${SAMPLE}.bam" \
        -o "${RESULTS_DIR}/${SAMPLE}.vcf.gz"

    # Compress and index the VCF file
    bcftools view -Oz -o "${RESULTS_DIR}/${SAMPLE}.vcf.gz" "${RESULTS_DIR}/${SAMPLE}.vcf"
    bcftools index "${RESULTS_DIR}/${SAMPLE}.vcf.gz"
done

# Collapse variants across samples into a single TSV file
cat > "${RESULTS_DIR}/collapsed.tsv" <<EOF
sample	chrom	pos	ref	alt	af
EOF

for SAMPLE in "${SAMPLES[@]}"; do
    # Extract relevant columns from the VCF for each sample
    bcftools view -H "${RESULTS_DIR}/${SAMPLE}.vcf.gz" | \
        awk -v sample="${SAMPLE}" '
            $1 == "chrM" {
                split($4, a, "/");
                ref = a[1];
                alt = a[length(a)];
                af = $(NF);
                printf("%s\tchrM\t%s\t%s\t%s\t%.3f\n", sample, $2, ref, alt, af);
            }
        ' >> "${RESULTS_DIR}/collapsed.tsv"
done

# Make the script idempotent: if results/ directory already contains all expected files,
# exit successfully without redoing any work
if [ -d "${RESULTS_DIR}" ] && \
   [ -f "${RESULTS_DIR}/M117-bl.bam" ] && [ -f "${RESULTS_DIR}/M117-bl.bam.bai" ] && \
   [ -f "${RESULTS_DIR}/M117-bl.vcf.gz" ] && [ -f "${RESULTS_DIR}/M117-bl.vcf.gz.tbi" ] && \
   [ -f "${RESULTS_DIR}/M117-ch.bam" ] && [ -f "${RESULTS_DIR}/M117-ch.bam.bai" ] && \
   [ -f "${RESULTS_DIR}/M117-ch.vcf.gz" ] && [ -f "${RESULTS_DIR}/M117-ch.vcf.gz.tbi" ] && \
   [ -f "${RESULTS_DIR}/M117C1-bl.bam" ] && [ -f "${RESULTS_DIR}/M117C1-bl.bam.bai" ] && \
   [ -f "${RESULTS_DIR}/M117C1-bl.vcf.gz" ] && [ -f "${RESULTS_DIR}/M117C1-bl.vcf.gz.tbi" ] && \
   [ -f "${RESULTS_DIR}/M117C1-ch.bam" ] && [ -f "${RESULTS_DIR}/M117C1-ch.bam.bai" ] && \
   [ -f "${RESULTS_DIR}/M117C1-ch.vcf.gz" ] && [ -f "${RESULTS_DIR}/M117C1-ch.vcf.gz.tbi" ] && \
   [ -f "${RESULTS_DIR}/collapsed.tsv" ]; then
    exit 0
fi