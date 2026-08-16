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

    # Check if all outputs for this sample already exist and are valid
    if [[ -f "$BAM" && -f "$BAI" && -f "$VCF_GZ" && -f "$TBI" ]]; then
        continue
    fi

    # Align reads using BWA-MEM
    bwa mem -t "$THREADS" -R "@RG\tID:${SAMPLE}\tSM:${SAMPLE}" "$REF" "$R1" "$R2" | \
        samtools view -bS -@ "$THREADS" -o "$BAM"

    # Sort and index BAM
    samtools sort -@ "$THREADS" -o "$BAM" "$BAM"
    samtools index -@ "$THREADS" "$BAM"

    # Call variants using LoFreq
    lofreq call -f "$REF" -o "${OUT_DIR}/${SAMPLE}.vcf" --call-indels -x 10 -t "$THREADS" "$BAM"

    # Filter and annotate VCF (optional, but good practice)
    # Here we just compress and index the VCF
    bgzip -c "${OUT_DIR}/${SAMPLE}.vcf" > "$VCF_GZ"
    tabix -p vcf "$VCF_GZ"

    # Clean up intermediate VCF
    rm -f "${OUT_DIR}/${SAMPLE}.vcf"
done

# Create collapsed TSV
COLLAPSED="${OUT_DIR}/collapsed.tsv"
if [[ ! -f "$COLLAPSED" ]]; then
    echo -e "sample\tchrom\tpos\tref\talt\taf" > "$COLLAPSED"
    
    for SAMPLE in "${SAMPLES[@]}"; do
        VCF_GZ="${OUT_DIR}/${SAMPLE}.vcf.gz"
        
        # Extract variants and format as TSV
        bcftools query -f '%CHROM\t%POS\t%REF\t%ALT[\t%AF]\n' "$VCF_GZ" | \
            awk -v sample="$SAMPLE" '{print sample "\t" $0}' >> "$COLLAPSED"
    done
fi