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

    # Check if final output exists to skip processing (idempotency)
    if [[ -f "${TBI}" ]]; then
        continue
    fi

    # 1. Alignment with BWA-MEM
    # We use a temporary SAM file or pipe directly to samtools view
    # To ensure idempotency and avoid partial files, we check for BAM existence too, 
    # but since we skip if TBI exists, we assume intermediate steps are valid if final is missing.
    
    # Align
    bwa mem -t "${THREADS}" "${REF}" "${R1}" "${R2}" | \
        samtools view -bS -o "${BAM}"

    # 2. Sort and Index BAM
    samtools sort -@ "${THREADS}" -o "${BAM}" "${BAM}"
    samtools index "${BAM}"

    # 3. Variant Calling with Lofreq
    # lofreq call outputs VCF. We use --call-indels to be thorough, though mtDNA is mostly SNPs.
    # -f provides the reference for base quality recalibration context if needed, 
    # but primarily we just need it for the output VCF header/reference consistency.
    lofreq call -f "${REF}" -o "${OUT_DIR}/${SAMPLE}.vcf" --call-indels "${BAM}"

    # 4. Compress and Index VCF
    bgzip "${OUT_DIR}/${SAMPLE}.vcf"
    mv "${OUT_DIR}/${SAMPLE}.vcf.gz" "${VCF_GZ}"
    tabix -p vcf "${VCF_GZ}"
    
    # Clean up uncompressed VCF if it still exists (bgzip should have replaced it, but safe to ensure)
    rm -f "${OUT_DIR}/${SAMPLE}.vcf"
done

# 5. Collapse variants into a single TSV
# Columns: sample chrom pos ref alt af
COLLAPSED="${OUT_DIR}/collapsed.tsv"

# Write header
printf "sample\tchrom\tpos\tref\talt\taf\n" > "${COLLAPSED}"

for SAMPLE in "${SAMPLES[@]}"; do
    VCF_GZ="${OUT_DIR}/${SAMPLE}.vcf.gz"
    
    # Use bcftools query to extract fields.
    # %CHROM, %POS, %REF, %ALT are standard.
    # For AF (Allele Frequency), lofreq typically outputs it in the INFO field as AF or in FORMAT if genotyped.
    # Lofreq call by default outputs a VCF with INFO/AF for the population frequency of the variant at that site.
    # Let's check standard lofreq output. It usually puts AF in INFO.
    # If multiple alts exist, we might need to handle them, but mtDNA is usually simple.
    
    # We use bcftools query. 
    # Fields: Sample name (hardcoded per loop), CHROM, POS, REF, ALT, INFO/AF
    # Note: bcftools query -f allows formatting.
    
    # Extracting AF from INFO field. Lofreq uses 'AF' key in INFO.
    # If a site has multiple alts, lofreq might list them separately or together. 
    # Standard VCF practice for multi-allelic sites: one line with ALT=A,T and AF=0.1,0.2.
    # We want one row per variant allele ideally? The prompt asks for "collapsed.tsv".
    # Usually, a simple extraction is preferred. If multi-allelic, we might split or keep as is.
    # Given the small size of mtDNA and typical amplicon data, let's assume standard behavior.
    # We will extract AF from INFO. If missing, default to . (or 0).
    
    bcftools query -f "%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "${VCF_GZ}" | \
    while IFS=$'\t' read -r CHROM POS REF ALT AF; do
        # Handle cases where AF might be missing or empty
        if [[ -z "${AF}" ]]; then
            AF="."
        fi
        
        # If there are multiple alts and multiple AFs, they correspond positionally.
        # However, for a simple TSV collapse, often one row per VCF line is expected unless specified otherwise.
        # The prompt asks for "sample chrom pos ref alt af". 
        # If ALT is "A,T" and AF is "0.1,0.2", should we split?
        # Standard bioinformatics "collapse" usually implies merging samples, not necessarily normalizing multi-allelic sites into rows.
        # However, to be safe and clean, if the user wants a flat table, keeping VCF structure (one line per site) is standard.
        # Let's output one line per VCF record.
        
        printf "%s\t%s\t%s\t%s\t%s\t%s\n" "${SAMPLE}" "${CHROM}" "${POS}" "${REF}" "${ALT}" "${AF}"
    done >> "${COLLAPSED}"
done