#!/usr/bin/env bash
set -euo pipefail

# Configuration
REF="data/ref/chrM.fa"
RAW_DIR="data/raw"
OUT_DIR="results"
THREADS=4

SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

# Create output directory if it doesn't exist
mkdir -p "$OUT_DIR"

# Index reference if not already indexed
if [[ ! -f "${REF}.bwt" ]]; then
    bwa index "$REF"
fi

# Process each sample
for SAMPLE in "${SAMPLES[@]}"; do
    R1="${RAW_DIR}/${SAMPLE}_1.fq.gz"
    R2="${RAW_DIR}/${SAMPLE}_2.fq.gz"
    BAM="${OUT_DIR}/${SAMPLE}.bam"
    BAI="${BAM}.bai"
    VCF_GZ="${OUT_DIR}/${SAMPLE}.vcf.gz"
    TBI="${VCF_GZ}.tbi"

    # Check if final VCF is already present and valid; if so, skip sample
    if [[ -f "$VCF_GZ" && -f "$TBI" ]]; then
        continue
    fi

    # Alignment with BWA-MEM
    bwa mem -t "$THREADS" -R "@RG\tID:${SAMPLE}\tSM:${SAMPLE}" "$REF" "$R1" "$R2" | \
    samtools view -b -@ "$THREADS" -o "$BAM"

    # Sort and index BAM
    samtools sort -@ "$THREADS" -o "$BAM" "$BAM"
    samtools index -@ "$THREADS" "$BAM"

    # Variant calling with Lofreq (haploid mitochondrial genome)
    # Using --call-indels to capture structural variants if any, though mostly SNPs expected
    # -x 0.01 sets a low minimum allele frequency threshold suitable for mtDNA heteroplasmy detection
    lofreq call -f "$REF" --min-af 0.01 -o "${SAMPLE}.vcf.tmp" "$BAM"

    # Filter and normalize variants with bcftools
    # Keep only high quality variants, filter by depth to avoid low coverage regions
    bcftools view -i 'QUAL>30 && DP>10' "${SAMPLE}.vcf.tmp" | \
    bcftools norm -m -any -f "$REF" | \
    bgzip -c > "$VCF_GZ"

    # Index the VCF
    tabix -p vcf "$VCF_GZ"

    # Clean up temporary files
    rm -f "${SAMPLE}.vcf.tmp"
done

# Generate collapsed TSV from all sample VCFs
{
    printf "sample\tchrom\tpos\tref\talt\taf\n"
    for SAMPLE in "${SAMPLES[@]}"; do
        VCF_GZ="${OUT_DIR}/${SAMPLE}.vcf.gz"
        if [[ ! -f "$VCF_GZ" ]]; then
            continue
        fi
        # Extract relevant fields: CHROM, POS, REF, ALT, AF (from INFO field)
        # bcftools query is used to extract specific columns
        # AF is typically in the INFO field for lofreq output
        bcftools query -f '%CHROM\t%POS\t%REF\t%ALT[\t%INFO/AF]\n' "$VCF_GZ" | \
        while IFS=$'\t' read -r CHROM POS REF ALT AF; do
            # Handle cases where AF might be missing or multiple values
            if [[ -z "$AF" ]]; then
                AF="NA"
            fi
            printf "%s\t%s\t%s\t%s\t%s\t%s\n" "$SAMPLE" "$CHROM" "$POS" "$REF" "$ALT" "$AF"
        done
    done
} > "${OUT_DIR}/collapsed.tsv"