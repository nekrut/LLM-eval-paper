#!/usr/bin/env bash
set -euo pipefail

# Directory setup
RAW_DIR="data/raw"
REF_DIR="data/ref"
OUT_DIR="results"
mkdir -p "$OUT_DIR"

# Tool inventory
BWA="bwa"
SAMTOOLS="samtools"
BCFTOOLS="bcftools"
TABIX="tabix"
LOFREQ="lofreq"
SEQKIT="seqkit"

# Reference genome path
REF_FA="$REF_DIR/chrM.fa"

# Sample list
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

# Function to check if a file exists and is non-empty
file_exists() {
    [ -s "$1" ]
}

# Function to check if a file is already processed (exists and has index)
is_processed() {
    local sample="$1"
    local file_type="$2" # bam, vcf
    local ext="$3"       # .bam, .vcf.gz
    local idx_ext="$4"   # .bai, .tbi
    local base_file="$OUT_DIR/${sample}.${file_type}${ext}"
    local idx_file="$OUT_DIR/${sample}.${file_type}${idx_ext}"
    file_exists "$base_file" && file_exists "$idx_file"
}

# 1. Index reference genome (if not already indexed)
if ! file_exists "$REF_FA.bai"; then
    echo "Indexing reference genome..."
    "$SAMTOOLS" faidx "$REF_FA"
    "$BWA" index "$REF_FA"
fi

# 2. Process each sample
for SAMPLE in "${SAMPLES[@]}"; do
    # Input files
    R1="$RAW_DIR/${SAMPLE}_1.fq.gz"
    R2="$RAW_DIR/${SAMPLE}_2.fq.gz"

    # Check if input files exist
    if ! file_exists "$R1" || ! file_exists "$R2"; then
        echo "Error: Input files not found for sample $SAMPLE"
        exit 1
    fi

    # BAM file paths
    BAM="$OUT_DIR/${SAMPLE}.bam"
    BAM_BAI="$OUT_DIR/${SAMPLE}.bam.bai"

    # VCF file paths
    VCF="$OUT_DIR/${SAMPLE}.vcf.gz"
    VCF_TBI="$OUT_DIR/${SAMPLE}.vcf.gz.tbi"

    # Skip if already processed
    if is_processed "$SAMPLE" "bam" ".bam" ".bai"; then
        echo "Skipping $SAMPLE (BAM already processed)"
        continue
    fi

    # Align reads
    echo "Aligning $SAMPLE..."
    "$BWA" mem -t 4 "$REF_FA" "$R1" "$R2" | "$SAMTOOLS" view -b - > "$BAM"
    "$SAMTOOLS" index "$BAM"

    # Call variants
    echo "Calling variants for $SAMPLE..."
    "$LOFREQ" call -f "$REF_FA" -o "$VCF" "$BAM"
    "$TABIX" -p vcf "$VCF"

    # Skip VCF processing if not needed for final output
    # (The task asks for VCF files, so we keep them)
done

# 3. Collapse VCFs into a single table
COLLAPSED="$OUT_DIR/collapsed.tsv"
COLLAPSED_TBI="$OUT_DIR/collapsed.tsv.tbi"

# Check if collapsed file already exists and is valid
if file_exists "$COLLAPSED" && file_exists "$COLLAPSED_TBI"; then
    echo "Skipping collapse (already exists)"
else
    echo "Collapsing VCFs..."
    # Concatenate all VCFs
    "$BCFTOOLS" concat -o "$COLLAPSED" "$OUT_DIR"/*.vcf.gz
    "$TABIX" -p vcf "$COLLAPSED"
fi

echo "Done."
exit 0