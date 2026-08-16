#!/usr/bin/env bash
set -euo pipefail

THREADS=4
REF="data/ref/chrM.fa"
RAW_DIR="data/raw"
OUT_DIR="results"

mkdir -p "$OUT_DIR"

# Index reference if not already indexed
if [[ ! -f "${REF}.bwt" ]]; then
    bwa index "$REF"
fi

SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

for SAMPLE in "${SAMPLES[@]}"; do
    BAM="$OUT_DIR/${SAMPLE}.bam"
    VCF="$OUT_DIR/${SAMPLE}.vcf.gz"

    # Mapping and Sorting
    if [[ ! -f "$BAM" ]]; then
        bwa mem -t "$THREADS" "$REF" \
            "$RAW_DIR/${SAMPLE}_1.fq.gz" \
            "$RAW_DIR/${SAMPLE}_2.fq.gz" | \
            samtools sort -@ "$THREADS" -o "$BAM" -
        samtools index "$BAM"
    fi

    # Variant Calling with LoFreq
    if [[ ! -f "$VCF" ]]; then
        lofreq call -i "$BAM" -r "$REF" -o "${VCF%.gz}" \
            --threads "$THREADS"
        bgzip -c "${VCF%.gz}" > "$VCF"
        rm "${VCF%.gz}"
        tabix -p vcf "$VCF"
    fi
done

# Collapse results into TSV
COLLAPSED="$OUT_DIR/collapsed.tsv"
if [[ ! -f "$COLLAPSED" ]]; then
    printf "sample\tchrom\tpos\tref\talt\taf\n" > "$COLLAPSED"
    for SAMPLE in "${SAMPLES[@]}"; do
        VCF="$OUT_DIR/${SAMPLE}.vcf.gz"
        # Extract POS, REF, ALT and calculate AF from INFO field (LoFreq provides AF)
        # LoFreq VCF format: INFO contains AF=0.xxx
        bcftools query -f "${SAMPLE}\t%CHROM\t%POS\t%REF\t%ALT\t[%AF]\n" "$VCF" >> "$COLLAPSED"
    done
fi