#!/usr/bin/env bash
set -euo pipefail

# Configuration
REF="data/ref/chrM.fa"
RAW_DIR="data/raw"
OUT_DIR="results"
THREADS=4

SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

# Create output directory if it doesn't exist
mkdir -p "${OUT_DIR}"

# Index reference if not already indexed
if [[ ! -f "${REF}.bwt" ]]; then
    bwa index "${REF}"
fi

# Process each sample
for SAMPLE in "${SAMPLES[@]}"; do
    R1="${RAW_DIR}/${SAMPLE}_1.fq.gz"
    R2="${RAW_DIR}/${SAMPLE}_2.fq.gz"
    BAM="${OUT_DIR}/${SAMPLE}.bam"
    BAI="${BAM}.bai"
    VCF_GZ="${OUT_DIR}/${SAMPLE}.vcf.gz"
    TBI="${VCF_GZ}.tbi"

    # Check if all outputs for this sample already exist and are valid
    if [[ -f "${BAM}" && -f "${BAI}" && -f "${VCF_GZ}" && -f "${TBI}" ]]; then
        continue
    fi

    # Align reads using BWA
    bwa mem -t "${THREADS}" "${REF}" "${R1}" "${R2}" | \
        samtools view -b -o "${BAM}" -

    # Sort and index BAM
    samtools sort -@ "${THREADS}" -o "${BAM}" "${BAM}"
    samtools index "${BAM}"

    # Call variants using LoFreq
    lofreq call --call-indels -f "${REF}" -o "${VCF_GZ}" "${BAM}"

    # Index VCF
    tabix -p vcf "${VCF_GZ}"
done

# Generate collapsed TSV
COLLAPSED="${OUT_DIR}/collapsed.tsv"

# Check if collapsed.tsv already exists and has content (header + data)
if [[ -f "${COLLAPSED}" ]] && [[ $(wc -l < "${COLLAPSED}") -gt 1 ]]; then
    exit 0
fi

# Write header
printf "sample\tchrom\tpos\tref\talt\taf\n" > "${COLLAPSED}"

# Process each sample VCF and append to collapsed TSV
for SAMPLE in "${SAMPLES[@]}"; do
    VCF_GZ="${OUT_DIR}/${SAMPLE}.vcf.gz"
    
    # Extract variant information from VCF
    # Format: sample chrom pos ref alt af
    bcftools query -f '%CHROM\t%POS\t%REF\t%ALT[\t%INFO/AF]\n' "${VCF_GZ}" | \
        awk -v sample="${SAMPLE}" '{print sample "\t" $0}' >> "${COLLAPSED}"
done