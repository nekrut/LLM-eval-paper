#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
REF="data/ref/chrM.fa"
OUT_DIR="results"

mkdir -p "$OUT_DIR"

# BWA requires indices in the same directory as the fasta. 
# To avoid modifying data/ref/, we copy the reference to results/.
cp "$REF" "$OUT_DIR/chrM.fa"
if [[ ! -f "$OUT_DIR/chrM.fa.bwt" ]]; then
    bwa index "$OUT_DIR/chrM.fa"
fi

for SAMPLE in "${SAMPLES[@]}"; do
    R1="data/raw/${SAMPLE}_1.fq.gz"
    R2="data/raw/${SAMPLE}_2.fq.gz"
    BAM="$OUT_DIR/${SAMPLE}.bam"
    VCF_GZ="$OUT_DIR/${SAMPLE}.vcf.gz"

    if [[ ! -f "$BAM" ]]; then
        bwa mem -t "$THREADS" "$OUT_DIR/chrM.fa" "$R1" "$R2" | \
        samtools sort -@ "$THREADS" -o "$BAM" -
    fi

    if [[ ! -f "$BAM.bai" ]]; then
        samtools index -@ "$THREADS" "$BAM"
    fi

    if [[ ! -f "$VCF_GZ" ]]; then
        lofreq call -f "$OUT_DIR/chrM.fa" -b "$BAM" > "$OUT_DIR/${SAMPLE}.vcf"
        bcftools view -Oz -o "$VCF_GZ" "$OUT_DIR/${SAMPLE}.vcf"
        rm "$OUT_DIR/${SAMPLE}.vcf"
    fi

    if [[ ! -f "$VCF_GZ.tbi" ]]; then
        tabix -p vcf "$VCF_GZ"
    fi
done

# Create collapsed table
printf "sample\tchrom\tpos\tref\talt\taf\n" > "$OUT_DIR/collapsed.tsv"
for SAMPLE in "${SAMPLES[@]}"; do
    VCF_GZ="$OUT_DIR/${SAMPLE}.vcf.gz"
    if [[ -f "$VCF_GZ" ]]; then
        bcftools query -f "${SAMPLE}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "$VCF_GZ" >> "$OUT_DIR/collapsed.tsv"
    fi
done