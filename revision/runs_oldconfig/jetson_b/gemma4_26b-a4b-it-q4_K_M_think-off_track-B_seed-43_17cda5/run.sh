#!/usr/bin/env bash
set -euo pipefail

THREADS=4
REF="data/ref/chrM.fa"
RAW_DIR="data/raw"
OUT_DIR="results"

mkdir -p "$OUT_DIR"

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

    if [[ -f "$BAM" && -f "$BAM.bai" && -f "$Vcf" ]]; then
        continue
    fi

    R1="${RAW_DIR}/${SAMPLE}_1.fq.gz"
    R2="${RAW_DIR}/${SAMPLE}_2.fq.gz"

    bwa mem -t "$THREADS" "$REF" "$R1" "$R2" | \
    samtools view -@ "$THREADS" -bS - | \
    samtools sort -@ "$THREADS" -o "$BAM"

    samtools index "$BAM"

    if [[ ! -f "$VCF" ]]; then
        lofreq call --region chrM:1-16569 -f "$REF" "$BAM" | \
        bcftools view -v snps | \
        bcftools compress -f -o "$VCF"
        
        if [[ ! -f "${VCF}.tbi" ]]; then
            tabix -p vcf "$VCF"
        fi
    fi
done

COLLAPSED="$OUT_DIR/collapsed.tsv"
if [[ ! -f "$COLLAPSED" ]]; then
    echo -e "sample\tchrom\tpos\tref\talt\taf" > "$COLLAPSED"
    for SAMPLE in "${SAMPLES[@]}"; do
        VCF="$OUT_DIR/${SAMPLE}.vcf.gz"
        if [[ -f "$VCF" ]]; then
            bcftools query -f "$SAMPLE\t%CHROM\t%POS\t%REF\t%ALT\t%AF\n" "$VCF" >> "$COLLAPSED"
        fi
    done
fi

exit 0