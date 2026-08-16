#!/usr/bin/env bash
set -euo pipefail

# Directories
RAW_DIR="data/raw"
REF_DIR="data/ref"
OUT_DIR="results"

# Reference
REF="$REF_DIR/chrM.fa"

# Samples
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

# Ensure output directory exists
mkdir -p "$OUT_DIR"

# Index reference if not already indexed
if [ ! -f "$REF.bwt" ]; then
    bwa index "$REF"
    samtools faidx "$REF"
fi

# Process each sample
for SAMPLE in "${SAMPLES[@]}"; do
    R1="${RAW_DIR}/${SAMPLE}_1.fq.gz"
    R2="${RAW_DIR}/${SAMPLE}_2.fq.gz"
    
    # Check if outputs already exist
    BAM="$OUT_DIR/${SAMPLE}.bam"
    VCF="$OUT_DIR/${SAMPLE}.vcf.gz"
    
    if [ -f "$BAM" ] && [ -f "$VCF" ]; then
        continue
    fi
    
    # Align
    bwa mem -t 4 "$REF" "$R1" "$R2" | \
    samtools view -b -F 4 - > "$BAM"
    
    # Sort and index
    samtools sort -@ 2 -o "${BAM}.tmp" "$BAM"
    mv "${BAM}.tmp" "$BAM"
    samtools index "$BAM"
    
    # Call variants
    lofreq call-parallel -f "$REF" -o "${VCF}.tmp" -m indel -t 2 "$BAM"
    
    # Convert and index VCF
    bcftools view -Oz -o "$VCF" "${VCF}.tmp"
    tabix -p vcf "$VCF"
done

# Collapse VCFs
VCF_LIST=""
for SAMPLE in "${SAMPLES[@]}"; do
    VCF_LIST="$VCF_LIST $OUT_DIR/${SAMPLE}.vcf.gz"
done

bcftools concat -Oz -o "$OUT_DIR/collapsed.vcf.gz" $VCF_LIST
tabix -p vcf "$OUT_DIR/collapsed.vcf.gz"

# Extract and format columns
bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%AF\n' "$OUT_DIR/collapsed.vcf.gz" | \
awk '{print $1"\t"$2"\t"$3"\t"$4"\t"$5}' > "$OUT_DIR/collapsed.tsv"

# Cleanup temporary files
rm -f "$OUT_DIR/collapsed.vcf.gz" "$OUT_DIR/collapsed.vcf.gz.tbi"
rm -f "$OUT_DIR/collapsed.tmp" "$OUT_DIR/collapsed.tsv.tmp"

exit 0