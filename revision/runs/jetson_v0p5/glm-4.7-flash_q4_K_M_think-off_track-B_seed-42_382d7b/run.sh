#!/usr/bin/env bash
set -euo pipefail

# Directory setup
RAW_DIR="data/raw"
REF_DIR="data/ref"
OUT_DIR="results"

# Create output directory if it doesn't exist
mkdir -p "$OUT_DIR"

# Define samples
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

# Function to check if a file exists and is non-empty
check_file() {
    local file="$1"
    if [[ ! -s "$file" ]]; then
        echo "Error: File $file is missing or empty." >&2
        exit 1
    fi
}

# Check input files
for sample in "${SAMPLES[@]}"; do
    check_file "$RAW_DIR/${sample}_1.fq.gz"
    check_file "$RAW_DIR/${sample}_2.fq.gz"
done

# Index reference genome if not already indexed
if [[ ! -f "$REF_DIR/chrM.fa.bai" ]]; then
    bwa index "$REF_DIR/chrM.fa"
fi

# Run alignment and variant calling for each sample
for sample in "${SAMPLES[@]}"; do
    # Define input and output paths
    R1="$RAW_DIR/${sample}_1.fq.gz"
    R2="$RAW_DIR/${sample}_2.fq.gz"
    BAM="$OUT_DIR/${sample}.bam"
    VCF="$OUT_DIR/${sample}.vcf.gz"
    
    # Check if outputs already exist
    if [[ -f "$BAM" ]] && [[ -f "$BAM.bai" ]] && [[ -f "$VCF" ]] && [[ -f "$VCF.tbi" ]]; then
        continue
    fi
    
    # Align reads
    bwa mem -t 4 "$REF_DIR/chrM.fa" "$R1" "$R2" | \
    samtools view -b - > "$BAM"
    
    # Sort and index BAM
    samtools sort -@ 2 -o "${BAM}.sorted" "$BAM"
    samtools index "${BAM}.sorted"
    
    # Move sorted BAM to final location
    mv "${BAM}.sorted" "$BAM"
    samtools index "$BAM"
    
    # Call variants with lofreq
    lofreq call-parallel -f "$REF_DIR/chrM.fa" -o "$VCF" -m 0.02 -t 4 "$BAM"
    
    # Index VCF
    tabix -p vcf "$VCF"
done

# Collapse VCFs into a single TSV
# Using bcftools query to extract INFO fields and awk to format
bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "$OUT_DIR"/*.vcf.gz | \
awk '{print $1"\t"$2"\t"$3"\t"$4"\t"$5}' > "$OUT_DIR/collapsed.tsv"

# Exit successfully
exit 0