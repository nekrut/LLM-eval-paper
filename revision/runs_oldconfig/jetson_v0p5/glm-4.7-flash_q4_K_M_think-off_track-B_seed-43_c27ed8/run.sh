#!/usr/bin/env bash
set -euo pipefail

# Directories
RAW_DIR="data/raw"
REF_DIR="data/ref"
OUT_DIR="results"

# Ensure output directory exists
mkdir -p "$OUT_DIR"

# Reference genome path
REF="$REF_DIR/chrM.fa"

# Index reference if not already done
if [ ! -f "$REF.bai" ]; then
    samtools index "$REF"
fi

# Array of samples
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

# Loop through samples
for SAMPLE in "${SAMPLES[@]}"; do
    # Input files
    R1="$RAW_DIR/${SAMPLE}_1.fq.gz"
    R2="$RAW_DIR/${SAMPLE}_2.fq.gz"
    
    # Output files
    BAM="$OUT_DIR/${SAMPLE}.bam"
    BAM_BAI="$OUT_DIR/${SAMPLE}.bam.bai"
    VCF="$OUT_DIR/${SAMPLE}.vcf.gz"
    VCF_TBI="$OUT_DIR/${SAMPLE}.vcf.gz.tbi"

    # Check if outputs already exist
    if [ -f "$BAM" ] && [ -f "$BAM_BAI" ] && [ -f "$VCF" ] && [ -f "$VCF_TBI" ]; then
        continue
    fi

    # 1. Align reads with BWA
    bwa mem -t 4 "$REF" "$R1" "$R2" | \
    samtools view -b - > "$BAM"

    # 2. Sort and index BAM
    samtools sort -@ 2 -o "$BAM.tmp" "$BAM"
    mv "$BAM.tmp" "$BAM"
    samtools index "$BAM"

    # 3. Call variants with lofreq
    lofreq call-parallel -f "$REF" -m indel -q 20 -C 50 -o "$VCF" "$BAM"

    # 4. Index VCF
    tabix -p vcf "$VCF"
done

# 5. Collapse VCFs into a single TSV
# Using bcftools query to extract INFO fields and awk to format
bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "$OUT_DIR"/*.vcf.gz | \
awk 'NF==5 {print $1"\t"$2"\t"$3"\t"$4"\t"$5}' > "$OUT_DIR/collapsed.tsv"

exit 0