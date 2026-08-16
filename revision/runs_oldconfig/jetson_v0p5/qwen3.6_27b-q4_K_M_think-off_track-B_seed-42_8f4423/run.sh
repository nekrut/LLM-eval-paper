#!/usr/bin/env bash
set -euo pipefail

# Configuration
REF="data/ref/chrM.fa"
RAW_DIR="data/raw"
OUT_DIR="results"
THREADS=4

# Sample list (prefixes matching the R1/R2 files)
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

# Create output directory if it doesn't exist
mkdir -p "${OUT_DIR}"

# 1. Index Reference (idempotent: only if index missing)
if [[ ! -f "${REF}.bwt" ]]; then
    bwa index "${REF}"
fi

# 2. Process each sample
for SAMPLE in "${SAMPLES[@]}"; do
    R1="${RAW_DIR}/${SAMPLE}_1.fq.gz"
    R2="${RAW_DIR}/${SAMPLE}_2.fq.gz"
    BAM="${OUT_DIR}/${SAMPLE}.bam"
    BAI="${BAM}.bai"
    VCF_GZ="${OUT_DIR}/${SAMPLE}.vcf.gz"
    TBI="${VCF_GZ}.tbi"

    # Check if final VCF is already present; if so, skip sample processing
    if [[ -f "${VCF_GZ}" && -f "${TBI}" ]]; then
        continue
    fi

    # Align with BWA-MEM
    bwa mem -t ${THREADS} "${REF}" "${R1}" "${R2}" | \
        samtools view -bS -@ ${THREADS} -o "${BAM}"

    # Sort and Index BAM
    samtools sort -@ ${THREADS} -o "${BAM}" "${BAM}"
    samtools index -@ ${THREADS} "${BAM}"

    # Variant Calling with Lofreq (haploid mitochondrial genome)
    # lofreq call outputs VCF. We use --call-indels to be thorough, though mtDNA is mostly SNPs.
    # -x removes duplicates if marked, but we didn't mark them. 
    # We rely on lofreq's internal handling or just standard calling.
    # Note: lofreq expects a BAM. 
    lofreq call --call-indels -f "${REF}" -o "${OUT_DIR}/${SAMPLE}.vcf" "${BAM}"

    # Normalize VCF (optional but good practice) and Compress
    # bcftools norm can help with left-alignment, though bwa/lofreq usually do well.
    # We will compress directly if not normalized, or normalize then compress.
    # Let's just compress the raw lofreq output to save time, as requested tools allow simple compression.
    
    # Compress VCF
    bgzip -c "${OUT_DIR}/${SAMPLE}.vcf" > "${VCF_GZ}"
    
    # Index VCF
    tabix -p vcf "${VCF_GZ}"
    
    # Clean up intermediate uncompressed VCF
    rm -f "${OUT_DIR}/${SAMPLE}.vcf"
done

# 3. Collapse all VCFs into a single TSV
# Columns: sample  chrom  pos  ref  alt  af

COLLAPSED="${OUT_DIR}/collapsed.tsv"

# Write Header
printf "sample\tchrom\tpos\tref\talt\taf\n" > "${COLLAPSED}"

for SAMPLE in "${SAMPLES[@]}"; do
    VCF_GZ="${OUT_DIR}/${SAMPLE}.vcf.gz"
    
    # Extract variants using bcftools query
    # %CHROM, %POS, %REF, %ALT, %INFO/AF (or DP4 based calculation if AF not present)
    # Lofreq usually outputs AF in INFO field. If not, we might need to calculate from AD/DP.
    # Standard lofreq VCF has AF in INFO. Let's assume standard output.
    # Format: sample chrom pos ref alt af
    
    bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "${VCF_GZ}" | \
    while IFS=$'\t' read -r CHROM POS REF ALT AF; do
        # Handle missing AF (replace . with 0 or calculate? Usually lofreq provides it)
        if [[ "${AF}" == "." || -z "${AF}" ]]; then
            AF="0"
        fi
        printf "%s\t%s\t%s\t%s\t%s\t%s\n" "${SAMPLE}" "${CHROM}" "${POS}" "${REF}" "${ALT}" "${AF}"
    done >> "${COLLAPSED}"
done