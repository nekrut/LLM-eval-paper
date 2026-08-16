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
    if [[ ! -f "${bam}" ]]; then
        bwa mem -t ${THREADS} "${REF}" "${r1}" "${r2}" | \
            samtools view -bS -o "${bam}"
    fi

    # Sort and index BAM if not already done
    if [[ ! -f "${bai}" ]]; then
        samtools sort -@ ${THREADS} -o "${bam}" "${bam}"
        samtools index "${bam}"
    fi

    # Variant calling with LoFreq
    # LoFreq outputs VCF to stdout, we pipe to bgzip to create compressed VCF
    if [[ ! -f "${vcf_gz}" ]]; then
        lofreq call-fast \
            --bams "${bam}" \
            --ref "${REF}" \
            --min-qual 20 \
            --min-af 0.01 \
            --threads ${THREADS} | \
            bgzip -c > "${vcf_gz}"
    fi

    # Index VCF if not already done
    if [[ ! -f "${tbi}" ]]; then
        tabix -p vcf "${vcf_gz}"
    fi
}

# Process all samples
for sample in "${SAMPLES[@]}"; do
    process_sample "${sample}"
done

# Generate collapsed.tsv
# Columns: sample  chrom  pos  ref  alt  af
COLLAPSED="${OUT_DIR}/collapsed.tsv"

if [[ ! -f "${COLLAPSED}" ]]; then
    # Header
    printf "sample\tchrom\tpos\tref\talt\taf\n" > "${COLLAPSED}"

    for sample in "${SAMPLES[@]}"; do
        vcf_gz="${OUT_DIR}/${sample}.vcf.gz"
        
        # Extract variants from VCF using bcftools query
        # %CHROM, %POS, %REF, %ALT, and calculate AF from FORMAT/AF or INFO/AF
        # LoFreq typically puts allele frequency in the INFO field as AF=... or in FORMAT.
        # Let's check standard LoFreq output. Usually INFO has AF.
        # If INFO AF is missing, we might need to look at FORMAT. 
        # Standard bcftools query for VCF4.2:
        
        bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "${vcf_gz}" | \
        while IFS=$'\t' read -r chrom pos ref alt af; do
            # Handle multi-allelic sites if necessary, but LoFreq usually splits them.
            # If AF is missing or '.', we might skip or handle it.
            # Ensure AF is a number. If '.' replace with 0 or skip? 
            # Let's assume valid calls have AF.
            if [[ "${af}" == "." || -z "${af}" ]]; then
                continue
            fi
            printf "%s\t%s\t%s\t%s\t%s\t%s\n" "${sample}" "${chrom}" "${pos}" "${ref}" "${alt}" "${af}"
        done >> "${COLLAPSED}"
    done
fi