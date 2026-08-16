#!/usr/bin/env bash
set -euo pipefail

# Configuration
REF="data/ref/chrM.fa"
RAW_DIR="data/raw"
OUT_DIR="results"
THREADS=4

# Sample list (prefixes)
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

# Create output directory if it doesn't exist
mkdir -p "${OUT_DIR}"

# 1. Index Reference (if not already indexed)
if [[ ! -f "${REF}.bwt" ]]; then
    bwa index "${REF}"
fi

# 2. Per-sample processing
for SAMPLE in "${SAMPLES[@]}"; do
    R1="${RAW_DIR}/${SAMPLE}_1.fq.gz"
    R2="${RAW_DIR}/${SAMPLE}_2.fq.gz"
    BAM="${OUT_DIR}/${SAMPLE}.bam"
    BAI="${BAM}.bai"
    VCF_GZ="${OUT_DIR}/${SAMPLE}.vcf.gz"
    TBI="${VCF_GZ}.tbi"

    # Check if final VCF exists; if so, skip sample (idempotency)
    if [[ -f "${TBI}" ]]; then
        continue
    fi

    # Alignment with BWA-MEM
    bwa mem -t ${THREADS} "${REF}" "${R1}" "${R2}" | \
        samtools view -bS -o "${BAM}"

    # Sort and Index BAM
    samtools sort -@ ${THREADS} -o "${BAM}" "${BAM}"
    samtools index "${BAM}"

    # Variant Calling with LoFreq (sensitive for mtDNA)
    # --call-indels is default, but good to be explicit if needed. 
    # Using default settings which are generally robust for high-depth amplicons.
    lofreq call -f "${REF}" -o "${OUT_DIR}/${SAMPLE}.vcf" "${BAM}"

    # Normalize VCF (optional but good practice) and Compress/Index
    # LoFreq output is usually fine, but let's ensure it's bgzipped and indexed properly for downstream.
    if [[ ! -f "${VCF_GZ}" ]]; then
        bgzip -c "${OUT_DIR}/${SAMPLE}.vcf" > "${VCF_GZ}"
        tabix -p vcf "${VCF_GZ}"
        # Clean up uncompressed VCF to save space, though not strictly required by prompt
        rm -f "${OUT_DIR}/${SAMPLE}.vcf"
    fi
done

# 3. Collapse Variants into TSV
COLLAPSED="${OUT_DIR}/collapsed.tsv"

# Write Header
printf "sample\tchrom\tpos\tref\talt\taf\n" > "${COLLAPSED}"

for SAMPLE in "${SAMPLES[@]}"; do
    VCF_GZ="${OUT_DIR}/${SAMPLE}.vcf.gz"
    
    # Extract variants using bcftools query
    # FORMAT/AF is the allele frequency from LoFreq
    # We filter for PASS or . to avoid low-quality calls if desired, but prompt implies all called variants.
    # LoFreq outputs AF in INFO field as well as FORMAT. Let's use INFO/AF if available, or FORMAT.
    # Standard LoFreq VCF has AF in INFO.
    
    bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "${VCF_GZ}" | \
    while IFS=$'\t' read -r CHROM POS REF ALT AF; do
        # Handle missing AF (e.g., if not present, though LoFreq usually provides it)
        if [[ -z "${AF}" ]]; then
            AF="NA"
        fi
        printf "%s\t%s\t%s\t%s\t%s\t%s\n" "${SAMPLE}" "${CHROM}" "${POS}" "${REF}" "${ALT}" "${AF}"
    done >> "${COLLAPSED}"
done