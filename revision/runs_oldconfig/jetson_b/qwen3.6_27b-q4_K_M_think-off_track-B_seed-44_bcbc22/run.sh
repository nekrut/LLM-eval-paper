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

# Function to process a single sample
process_sample() {
    local sample="$1"
    local r1="${RAW_DIR}/${sample}_1.fq.gz"
    local r2="${RAW_DIR}/${sample}_2.fq.gz"
    local bam="${OUT_DIR}/${sample}.bam"
    local bai="${bam}.bai"
    local vcf_gz="${OUT_DIR}/${sample}.vcf.gz"
    local tbi="${vcf_gz}.tbi"

    # Check if final VCF is already present and valid (idempotency)
    if [[ -f "${vcf_gz}" && -f "${tbi}" ]]; then
        return 0
    fi

    # Alignment with BWA-MEM
    bwa mem -t "${THREADS}" "${REF}" "${r1}" "${r2}" | \
        samtools view -b -o "${bam}"

    # Sort and index BAM
    samtools sort -@ "${THREADS}" -o "${bam}" "${bam}"
    samtools index "${bam}"

    # Variant calling with LoFreq (sensitive for low-frequency variants)
    # Using --call-only to output VCF directly, filtering out low quality sites
    lofreq call --call-only -f "${REF}" -o "${OUT_DIR}/${sample}.vcf" "${bam}"

    # Compress and index VCF
    bgzip -c "${OUT_DIR}/${sample}.vcf" > "${vcf_gz}"
    tabix -p vcf "${vcf_gz}"

    # Clean up intermediate uncompressed VCF
    rm -f "${OUT_DIR}/${sample}.vcf"
}

# Process each sample
for sample in "${SAMPLES[@]}"; do
    process_sample "${sample}"
done

# Generate collapsed TSV
# Header
printf "sample\tchrom\tpos\tref\talt\taf\n" > "${OUT_DIR}/collapsed.tsv"

# Iterate over samples and extract variant info
for sample in "${SAMPLES[@]}"; do
    vcf_gz="${OUT_DIR}/${sample}.vcf.gz"
    
    # Use bcftools query to extract required fields
    # %CHROM, %POS, %REF, %ALT, %INFO/AF (or calculate from FORMAT/AD if needed)
    # LoFreq outputs AF in INFO field. If not present, we might need to parse FORMAT.
    # Standard LoFreq VCF has AF in INFO. Let's assume standard output.
    # If AF is missing in INFO, bcftools query might return '.'. 
    # We will use %INFO/AF. If that fails, we fallback to calculating from AD if necessary, 
    # but for simplicity and robustness with LoFreq, INFO/AF is standard.
    
    # Note: Some VCFs might not have AF in INFO. Let's check if we can get it from FORMAT/AD.
    # LoFreq typically puts AF in INFO. 
    # Format: sample chrom pos ref alt af
    
    bcftools query -f "%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "${vcf_gz}" | \
    while IFS=$'\t' read -r chrom pos ref alt af; do
        # If AF is missing or '.', try to get it from FORMAT/AD if possible, 
        # but for this script, we assume LoFreq provides AF in INFO.
        # If AF is empty, default to 0 or skip? The task asks for AF.
        # Let's ensure we don't print lines with missing AF if possible, 
        # or handle the '.' case.
        
        # Handle multi-allelic sites by splitting ALT and AF if necessary?
        # bcftools query handles multi-allelics by repeating lines if using %ALT/%INFO/AF correctly?
        # Actually, %ALT returns comma-separated alleles for multi-allelic sites.
        # %INFO/AF returns comma-separated frequencies.
        # We need to split them into separate rows.
        
        IFS=',' read -ra alts <<< "${alt}"
        IFS=',' read -ra afs <<< "${af}"
        
        for i in "${!alts[@]}"; do
            alt_allele="${alts[$i]}"
            af_val="${afs[$i]:-0.0}" # Default to 0 if missing
            
            # Skip non-SNPs/Indels or low quality if needed? Task doesn't specify filter, just "variant calling".
            # We include all called variants.
            
            printf "%s\t%s\t%s\t%s\t%s\t%s\n" "${sample}" "${chrom}" "${pos}" "${ref}" "${alt_allele}" "${af_val}"
        done
    done >> "${OUT_DIR}/collapsed.tsv"
done