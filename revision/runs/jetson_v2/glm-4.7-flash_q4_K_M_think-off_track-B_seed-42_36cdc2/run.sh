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

# Function to check if output exists and is valid
check_output() {
    local sample=$1
    local file=$2
    local type=$3 # bam, vcf, tbi, bai

    if [[ "$type" == "bam" ]]; then
        # Check if BAM file exists and is non-empty
        if [[ -f "$OUT_DIR/$sample.bam" ]] && [[ -s "$OUT_DIR/$sample.bam" ]]; then
            return 0
        fi
    elif [[ "$type" == "vcf" ]]; then
        # Check if VCF file exists and is non-empty
        if [[ -f "$OUT_DIR/$sample.vcf.gz" ]] && [[ -s "$OUT_DIR/$sample.vcf.gz" ]]; then
            return 0
        fi
    elif [[ "$type" == "tbi" ]]; then
        # Check if index file exists
        if [[ -f "$OUT_DIR/$sample.vcf.gz.tbi" ]]; then
            return 0
        fi
    elif [[ "$type" == "bai" ]]; then
        # Check if index file exists
        if [[ -f "$OUT_DIR/$sample.bam.bai" ]]; then
            return 0
        fi
    fi
    return 1
}

# Index reference genome if not already indexed
if [[ ! -f "$REF_DIR/chrM.fa.bai" ]]; then
    echo "Indexing reference genome..."
    samtools faidx "$REF_DIR/chrM.fa"
fi

# Process each sample
for sample in "${SAMPLES[@]}"; do
    # Check if outputs already exist
    if check_output "$sample" "" "bam" && check_output "$sample" "" "bai" && check_output "$sample" "" "vcf" && check_output "$sample" "" "tbi"; then
        echo "Skipping $sample: outputs already exist."
        continue
    fi

    # 1. Align reads to reference
    echo "Aligning $sample..."
    bwa mem -t 4 "$REF_DIR/chrM.fa" "$RAW_DIR/${sample}_1.fq.gz" "$RAW_DIR/${sample}_2.fq.gz" | \
        samtools view -b - > "$OUT_DIR/${sample}.bam"

    # 2. Sort BAM file
    echo "Sorting $sample..."
    samtools sort -@ 2 -o "$OUT_DIR/${sample}.sorted.bam" "$OUT_DIR/${sample}.bam"
    mv "$OUT_DIR/${sample}.sorted.bam" "$OUT_DIR/${sample}.bam"

    # 3. Index BAM file
    echo "Indexing $sample..."
    samtools index "$OUT_DIR/${sample}.bam"

    # 4. Call variants using lofreq
    echo "Calling variants for $sample..."
    lofreq call-parallel -f "$REF_DIR/chrM.fa" -o "$OUT_DIR/${sample}.vcf" -m indel -t 2 "$OUT_DIR/${sample}.bam"

    # 5. Convert VCF to BGZIP and index
    echo "Processing VCF for $sample..."
    bgzip -c "$OUT_DIR/${sample}.vcf" > "$OUT_DIR/${sample}.vcf.gz"
    tabix -p vcf "$OUT_DIR/${sample}.vcf.gz"
done

# 6. Collapse VCFs into a single table
echo "Collapsing VCFs..."
# Use bcftools to concatenate and then extract INFO fields
bcftools concat -Oz -o "$OUT_DIR/merged.vcf.gz" "$OUT_DIR"/*.vcf.gz
tabix -p vcf "$OUT_DIR/merged.vcf.gz"

# Use bcftools query to extract sample, chrom, pos, ref, alt, and INFO/AF
bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "$OUT_DIR/merged.vcf.gz" > "$OUT_DIR/collapsed.tsv"

# Add header
echo -e "sample\tchrom\tpos\tref\talt\taf" > "$OUT_DIR/collapsed.tsv"
cat "$OUT_DIR/collapsed.tsv" > "$OUT_DIR/collapsed.tsv.tmp"
mv "$OUT_DIR/collapsed.tsv.tmp" "$OUT_DIR/collapsed.tsv"

echo "Done."