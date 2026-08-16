#!/usr/bin/env bash
set -euo pipefail

THREADS=4
REF="data/ref/chrM.fa"
RAW_DIR="data/raw"
OUT_DIR="results"

mkdir -p "$OUT_DIR"

# Index reference if not present
if [[ ! -f "${REF}.bwt" ]]; then
    bwa index "$REF"
fi
if [[ ! -f "${REF}.fai" ]]; then
    samtools faidx "$REF"
fi

SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

for SAMPLE in "${SAMPLES[@]}"; do
    BAM="$OUT_DIR/${SAMPLE}.bam"
    VCF="$OUT_DIR/${SAMPLE}.vcf.gz"

    if [[ -f "$VCF" ]]; then
        continue
    fi

    R1="$RAW_DIR/${SAMPLE}_1.fq.gz"
    R2="$RAW_DIR/${SAMPLE}_2.fq.gz"

    # Alignment
    bwa mem -t "$THREADS" "$REF" "$R1" "$R2" | \
        samtools view -@ "$THREADS" -bS - | \
        samtools sort -@ "$THREADS" -o "$BAM"
    
    samtools index "$BAM"

    # Variant Calling using lofreq
    lofreq call -f "$REF" -o "$VCF" "$BAM"
    tabix -p vcf "$VCF"
done

# Create collapsed table
COLLAPSED="$OUT_DIR/collapsed.tsv"
if [[ ! -f "$COLLAPSED" ]]; then
    printf "sample\tchrom\tpos\tref\talt\taf\n" > "$COLLAPSED"
    for SAMPLE in "${SAMPLES[@]}"; do
        VCF="$OUT_DIR/${SAMPLE}.vcf.gz"
        # Extracting: CHROM, POS, REF, ALT, and AF (from INFO field)
        # Using bcftools query for robust parsing of the AF tag
        bcftools query -f "$SAMPLE\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "$VCF" >> "$COLLAPSED"
    done
fi

exit 0