#!/usr/bin/env bash
set -euo pipefail

# Configuration
REF="data/ref/chrM.fa"
RAW_DIR="data/raw"
OUT_DIR="results"
THREADS=4

# Create output directory if it doesn't exist
mkdir -p "$OUT_DIR"

# Index reference if not already present
if [ ! -f "${REF}.fai" ]; then
    samtools faidx "$REF"
fi

# List of samples
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

# Process each sample
for SAMPLE in "${SAMPLES[@]}"; do
    R1="${RAW_DIR}/${SAMPLE}_1.fq.gz"
    R2="${RAW_DIR}/${SAMPLE}_2.fq.gz"
    BAM="${OUT_DIR}/${SAMPLE}.bam"
    VCF_GZ="${OUT_DIR}/${SAMPLE}.vcf.gz"

    # Skip if BAM already exists (idempotency)
    if [ -f "$BAM" ] && [ -f "${BAM}.bai" ] && [ -f "$VCF_GZ" ] && [ -f "${VCF_GZ}.tbi" ]; then
        continue
    fi

    # 1. Alignment with BWA-MEM
    bwa mem -t "$THREADS" -R "@RG\tID:${SAMPLE}\tSM:${SAMPLE}\tPL:ILLUMINA" "$REF" "$R1" "$R2" | \
        samtools sort -@ "$THREADS" -o "$BAM" -

    # 2. Index BAM
    samtools index "$BAM"

    # 3. Variant Calling with LoFreq
    # LoFreq requires a base quality recalibration step internally or via input, 
    # but standard usage is: lofreq call -f ref -r regions -d dNV -o out.vcf in.bam
    # We use the BAM directly. LoFreq handles duplicate marking internally if needed, 
    # but for amplicon data, we usually want to keep all reads unless PCR duplicates are extreme.
    # However, standard lofreq call is sufficient for this task.
    
    # Create a temporary file for VCF before gzipping to ensure atomicity if possible, 
    # though lofreq can output directly to .vcf.gz in newer versions? 
    # LoFreq 2.1.5 outputs .vcf by default. We will gzip it manually.
    TEMP_VCF="${OUT_DIR}/${SAMPLE}.vcf"
    
    lofreq call -f "$REF" -r chrM -d dNV -o "$TEMP_VCF" "$BAM"

    # 4. Compress and Index VCF
    bgzip -c "$TEMP_VCF" > "$VCF_GZ"
    tabix -p vcf "$VCF_GZ"

    # Clean up temp VCF
    rm -f "$TEMP_VCF"
done

# 5. Collapse all VCFs into a single TSV
# Columns: sample chrom pos ref alt af
# We need to extract these fields from each .vcf.gz file.
# bcftools query is efficient for this.

# Header
printf "sample\tchrom\tpos\tref\talt\taf\n" > "${OUT_DIR}/collapsed.tsv"

for SAMPLE in "${SAMPLES[@]}"; do
    VCF_GZ="${OUT_DIR}/${SAMPLE}.vcf.gz"
    
    # Extract fields: CHROM, POS, REF, ALT, INFO/AF (or FORMAT/GT if AF not present)
    # LoFreq typically outputs AF in the INFO field as 'AF' or 'DP4'. 
    # Let's check standard LoFreq output. It usually has 'AF' in INFO.
    # If AF is missing, we might need to calculate from AD/DP in FORMAT.
    # However, for simplicity and robustness with LoFreq 2.1.5:
    # LoFreq outputs: CHROM POS ID REF ALT QUAL FILTER INFO FORMAT ...
    # INFO contains 'AF=...'
    
    bcftools query -f "%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "$VCF_GZ" | \
    while IFS=$'\t' read -r chrom pos ref alt af; do
        # Handle multi-allelic sites where AF might be comma-separated or missing for some alleles
        # LoFreq usually reports per-allele AF if multiple alts.
        # If AF is empty, skip or handle? Usually LoFreq provides AF.
        if [ -z "$af" ]; then
            continue
        fi
        
        # Split multi-allelic AFs if necessary (e.g., "0.1,0.2")
        IFS=',' read -ra af_array <<< "$af"
        IFS=',' read -ra alt_array <<< "$alt"
        
        for i in "${!alt_array[@]}"; do
            a_alt="${alt_array[$i]}"
            a_af="${af_array[$i]:-}"
            
            # If AF is missing for a specific allele, skip
            if [ -z "$a_af" ]; then
                continue
            fi
            
            printf "%s\t%s\t%s\t%s\t%s\t%s\n" "$SAMPLE" "$chrom" "$pos" "$ref" "$a_alt" "$a_af"
        done
    done >> "${OUT_DIR}/collapsed.tsv"
done