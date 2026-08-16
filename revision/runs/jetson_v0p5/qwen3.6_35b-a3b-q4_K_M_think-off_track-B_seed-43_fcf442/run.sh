#!/usr/bin/env bash
set -euo pipefail

# Create output directory
mkdir -p results

# Reference files
REF=data/ref/chrM.fa
REF_BWA="${REF}.amb"
REF_BWA_INDEXED=false

# Check if BWA index exists (idempotency)
if [[ ! -f "$REF_BWA" ]]; then
    bwa index "$REF"
fi

# Define samples and their read pairs
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

for SAMPLE in "${SAMPLES[@]}"; do
    R1="data/raw/${SAMPLE}_1.fq.gz"
    R2="data/raw/${SAMPLE}_2.fq.gz"
    BAM="results/${SAMPLE}.bam"
    BAI="${BAM}.bai"
    VCF_GZ="results/${SAMPLE}.vcf.gz"
    VCF_TBI="${VCF_GZ}.tbi"

    # Step 1: Alignment with BWA-MEM
    if [[ ! -f "$BAM" ]]; then
        bwa mem -t 4 "$REF" "$R1" "$R2" | samtools sort -@ 4 -o "$BAM" -
    fi

    # Step 2: Index BAM
    if [[ ! -f "$BAI" ]]; then
        samtools index -@ 4 "$BAM"
    fi

    # Step 3: Variant calling with LoFreq
    # LoFreq requires a FASTA reference and a BAM file.
    # It performs base quality recalibration internally based on mapping quality.
    if [[ ! -f "$VCF_GZ" ]]; then
        lofreq call-parallel \
            -f "$REF" \
            -d "$BAM" \
            -o "$VCF_GZ" \
            --no-indels \
            --min-cov 10 \
            --min-freq 0.005 \
            --threads 4
    fi

    # Step 4: Index VCF
    if [[ ! -f "$VCF_TBI" ]]; then
        tabix -p vcf "$VCF_GZ"
    fi
done

# Step 5: Collapse all VCFs into a single TSV
COLLAPSED="results/collapsed.tsv"

# Write header
printf "sample\tchrom\tpos\tref\talt\taf\n" > "$COLLAPSED"

for SAMPLE in "${SAMPLES[@]}"; do
    VCF_GZ="results/${SAMPLE}.vcf.gz"
    
    # Use bcftools query to extract fields: CHROM, POS, REF, ALT, INFO/AF
    # Note: LoFreq outputs AF in the INFO field as 'AF'. 
    # We need to handle multi-allelic sites if they exist, but typically for collapsed tables we want one row per variant.
    # bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' handles this well.
    # However, AF might be missing or formatted differently. LoFreq usually outputs AF in INFO.
    
    bcftools query -f "${SAMPLE}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "$VCF_GZ" >> "$COLLAPSED"
done

# Clean up any empty lines that might have been appended (though unlikely with strict formatting)
# Ensure no trailing newlines or issues, though standard bcftools output is clean.