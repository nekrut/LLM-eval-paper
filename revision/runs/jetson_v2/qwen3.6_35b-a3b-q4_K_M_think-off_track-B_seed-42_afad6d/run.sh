#!/usr/bin/env bash
set -euo pipefail

# Configuration
THREADS=4
REF="data/ref/chrM.fa"
RAW_DIR="data/raw"
RESULTS_DIR="results"

# Create results directory if it doesn't exist
mkdir -p "$RESULTS_DIR"

# Index reference if not already present
if [ ! -f "${REF}.fai" ]; then
    samtools faidx "$REF"
fi
if [ ! -f "${REF}.bwt" ]; then
    bwa index "$REF"
fi

# Define samples and their read files
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

# Function to process a single sample
process_sample() {
    local sample=$1
    local fq1="${RAW_DIR}/${sample}_1.fq.gz"
    local fq2="${RAW_DIR}/${sample}_2.fq.gz"
    local bam="${RESULTS_DIR}/${sample}.bam"
    local bai="${bam}.bai"
    local vcf_gz="${RESULTS_DIR}/${sample}.vcf.gz"
    local vcf_tbi="${vcf_gz}.tbi"

    # Skip if all outputs already exist (idempotency)
    if [ -f "$bam" ] && [ -f "$bai" ] && [ -f "$vcf_gz" ] && [ -f "$vcf_tbi" ]; then
        return 0
    fi

    # Step 1: Alignment with BWA-MEM
    # Using -M for mark shorter split hits as secondary (compatible with GATK/bcftools)
    bwa mem -t "$THREADS" -M "$REF" "$fq1" "$fq2" | \
        samtools view -b -@ "$THREADS" -o "$bam" -

    # Step 2: Sort BAM and generate index
    if [ ! -f "${bam}.sorted.bam" ]; then
        samtools sort -@ "$THREADS" -o "${bam}.sorted.bam" "$bam"
    fi
    
    # Replace unsorted bam with sorted one for downstream tools
    mv "${bam}.sorted.bam" "$bam"
    
    if [ ! -f "$bai" ]; then
        samtools index -@ "$THREADS" "$bam"
    fi

    # Step 3: Variant Calling with LoFreq
    # LoFreq requires a FASTA reference and a BAM file. It handles base quality recalibration internally.
    # We use the original uncompressed reference for lofreq's internal indexing if needed, 
    # but usually it just reads the faidx.
    
    if [ ! -f "$vcf_gz" ]; then
        lofreq call-parallel \
            -f "$REF" \
            -r "$bam" \
            -o "$vcf_gz" \
            --no-indels \
            --force \
            -t "$THREADS"
        
        # Generate VCF index
        if [ ! -f "$vcf_tbi" ]; then
            tabix -p vcf "$vcf_gz"
        fi
    fi
}

# Process all samples in parallel
for sample in "${SAMPLES[@]}"; do
    process_sample "$sample" &
done

wait

# Step 4: Collapse VCFs into a single TSV
# Header
printf "sample\tchrom\tpos\tref\talt\taf\n" > "${RESULTS_DIR}/collapsed.tsv"

for sample in "${SAMPLES[@]}"; do
    vcf_gz="${RESULTS_DIR}/${sample}.vcf.gz"
    
    # Extract INFO fields. LoFreq outputs AF in the INFO field as 'AF' or similar.
    # Standard VCF columns: CHROM POS ID REF ALT QUAL FILTER INFO FORMAT ...
    # We need: sample, chrom, pos, ref, alt, af
    
    # Use bcftools query to extract specific fields
    # LoFreq typically puts allele frequency in the INFO field as 'AF' or 'AF1'/'AF2'. 
    # For haploid/amplicon data, it's often just 'AF'. Let's check standard lofreq output.
    # Lofreq vcf output usually has: CHROM POS ID REF ALT QUAL FILTER INFO FORMAT
    # INFO contains: AF=...; ...
    
    bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "$vcf_gz" | \
    while IFS=$'\t' read -r chrom pos ref alt af; do
        # Handle multi-allelic sites or missing AF gracefully if needed, 
        # but for collapsed table we assume simple variants.
        # If AF is missing or empty, skip or handle? LoFreq usually provides it.
        if [ -n "$af" ]; then
            printf "%s\t%s\t%s\t%s\t%s\t%s\n" "$sample" "$chrom" "$pos" "$ref" "$alt" "$af"
        fi
    done >> "${RESULTS_DIR}/collapsed.tsv"
done

# Ensure the script exits successfully
exit 0