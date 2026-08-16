#!/usr/bin/env bash
set -euo pipefail

# Configuration
REF="data/ref/chrM.fa"
RAW_DIR="data/raw"
OUT_DIR="results"
THREADS=4

# Create output directory if it doesn't exist
mkdir -p "$OUT_DIR"

# Index reference if not already indexed
if [ ! -f "${REF}.fai" ]; then
    samtools faidx "$REF"
fi

# Define samples and their read files
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

for SAMPLE in "${SAMPLES[@]}"; do
    R1="${RAW_DIR}/${SAMPLE}_1.fq.gz"
    R2="${RAW_DIR}/${SAMPLE}_2.fq.gz"
    BAM="${OUT_DIR}/${SAMPLE}.bam"
    VCF_GZ="${OUT_DIR}/${SAMPLE}.vcf.gz"

    # Step 1: Alignment with BWA-MEM
    if [ ! -f "$BAM" ]; then
        bwa mem -t "$THREADS" "$REF" "$R1" "$R2" | \
            samtools sort -@ "$THREADS" -o "$BAM" -
        
        # Step 2: Index BAM
        samtools index "$BAM"
    fi

    # Step 3: Variant Calling with LoFreq
    if [ ! -f "$VCF_GZ" ]; then
        # LoFreq requires a reference FASTA and the sorted BAM
        lofreq call-parallel \
            -f "$REF" \
            -i "$BAM" \
            -o "${OUT_DIR}/${SAMPLE}.vcf" \
            --no-indels \
            --qual-min 0 \
            --min-cov 10 \
            --max-cov 10000 \
            --threads "$THREADS"

        # Compress and index VCF
        bgzip -c "${OUT_DIR}/${SAMPLE}.vcf" > "$VCF_GZ"
        tabix -p vcf "$VCF_GZ"
        
        # Clean up uncompressed VCF
        rm -f "${OUT_DIR}/${SAMPLE}.vcf"
    fi
done

# Step 4: Collapse VCFs into a single TSV
COLLAPSED="${OUT_DIR}/collapsed.tsv"

# Write header
printf "sample\tchrom\tpos\tref\talt\taf\n" > "$COLLAPSED"

for SAMPLE in "${SAMPLES[@]}"; do
    VCF_GZ="${OUT_DIR}/${SAMPLE}.vcf.gz"
    
    # Extract relevant columns from VCF: CHROM, POS, REF, ALT, INFO/AF (or FORMAT/GT based AF)
    # LoFreq outputs AF in the INFO field as 'AF' or similar. Let's check standard LoFreq output.
    # LoFreq vcf typically has: #CHROM POS ID REF ALT QUAL FILTER INFO FORMAT SAMPLE...
    # The AF is often in INFO as 'AF=...' or in the sample column if GT is present.
    # However, lofreq call-parallel usually outputs a VCF where the last column contains the genotype and quality.
    # Let's use bcftools to extract standard fields to be safe and consistent.
    
    bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "$VCF_GZ" 2>/dev/null | \
    while IFS=$'\t' read -r chrom pos ref alt af; do
        # Handle multi-allelic sites if necessary, but lofreq usually splits or reports best.
        # If AF is missing or empty, skip or set to 0? LoFreq should provide AF.
        if [ -n "$af" ]; then
            printf "%s\t%s\t%s\t%s\t%s\t%s\n" "$SAMPLE" "$chrom" "$pos" "$ref" "$alt" "$af"
        fi
    done >> "$COLLAPSED"
done

# Ensure the collapsed file is sorted by chrom, pos for consistency (optional but good practice)
# The header must remain at the top.
head -1 "$COLLAPSED" > "${OUT_DIR}/collapsed_sorted.tsv"
tail -n +2 "$COLLAPSED" | sort -t$'\t' -k2,2 -k3,3n >> "${OUT_DIR}/collapsed_sorted.tsv"
mv "${OUT_DIR}/collapsed_sorted.tsv" "$COLLAPSED"