#!/usr/bin/env bash
set -euo pipefail

# Configuration
REF="data/ref/chrM.fa"
RAW_DIR="data/raw"
OUT_DIR="results"
THREADS=4

# Create output directory
mkdir -p "$OUT_DIR"

# Index reference if not present
if [ ! -f "${REF}.fai" ]; then
    samtools faidx "$REF"
fi
if [ ! -f "${REF}.bwt" ]; then
    bwa index "$REF"
fi

# Define samples and their read files
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
    # but standard usage takes BAM and reference.
    # We use lofreq call to generate raw VCF.
    lofreq call -f "$REF" -i "$BAM" -o "${OUT_DIR}/${SAMPLE}.vcf" --no-indels --force

    # 4. Filter and Compress VCF with bcftools
    # Filter for basic quality metrics (QUAL > 20, DP >= 10) to clean up noise
    bcftools filter -e 'QUAL<20 || DP<10' "${OUT_DIR}/${SAMPLE}.vcf" | \
        bcftools view -m2 -M2 -v snps -O z -o "$VCF_GZ"

    # 5. Index VCF
    tabix -p vcf "$VCF_GZ"

    # Clean up intermediate uncompressed VCF if it exists
    rm -f "${OUT_DIR}/${SAMPLE}.vcf"
done

# Generate collapsed.tsv
# Header
printf "sample\tchrom\tpos\tref\talt\taf\n" > "${OUT_DIR}/collapsed.tsv"

# Extract variants from all samples and format them
for SAMPLE in "${SAMPLES[@]}"; do
    VCF_GZ="${OUT_DIR}/${SAMPLE}.vcf.gz"
    
    # Use bcftools query to extract fields: sample_name, chrom, pos, ref, alt, AF
    # FORMAT: %s\t%CHROM\t%POS\t%REF\t%ALT\t%AF
    bcftools query -f '%ID\t%CHROM\t%POS\t%REF\t%ALT\t%AF\n' "$VCF_GZ" | \
    while IFS=$'\t' read -r ID CHROM POS REF ALT AF; do
        # Handle missing values or multi-allelic sites if any slipped through (though we filtered for biallelic SNPs)
        if [ -z "$AF" ]; then
            AF="."
        fi
        
        # Output sample name, chrom, pos, ref, alt, af
        printf "%s\t%s\t%s\t%s\t%s\t%s\n" "$SAMPLE" "$CHROM" "$POS" "$REF" "$ALT" "$AF"
    done >> "${OUT_DIR}/collapsed.tsv"
done

# Ensure the file is sorted by sample then position for consistency (optional but good practice)
# The header must remain at the top.
head -n 1 "${OUT_DIR}/collapsed.tsv" > "${OUT_DIR}/collapsed_sorted.tsv"
tail -n +2 "${OUT_DIR}/collapsed.tsv" | sort -t$'\t' -k1,1 -k3,3n >> "${OUT_DIR}/collapsed_sorted.tsv"
mv "${OUT_DIR}/collapsed_sorted.tsv" "${OUT_DIR}/collapsed.tsv"