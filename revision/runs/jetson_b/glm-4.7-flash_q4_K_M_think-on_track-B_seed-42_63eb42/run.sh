#!/usr/bin/env bash
set -euo pipefail

RAW_DIR="data/raw"
REF_DIR="data/ref"
OUT_DIR="results"

mkdir -p "$OUT_DIR"

# 1. Reference Indexing
REF_FA="$REF_DIR/chrM.fa"
if [ ! -f "${REF_FA}.bwt" ]; then
    bwa index "$REF_FA"
fi

SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

# 2. Alignment
for sample in "${SAMPLES[@]}"; do
    BAM="$OUT_DIR/${sample}.bam"
    if [ ! -f "$BAM" ]; then
        bwa mem -t 4 "$REF_FA" "$RAW_DIR/${sample}_1.fq.gz" "$RAW_DIR/${sample}_2.fq.gz" | \
        samtools view -b - | \
        samtools sort -o "$BAM" -
        samtools index "$BAM"
    fi
done

# 3. Variant Calling
for sample in "${SAMPLES[@]}"; do
    VCF="$OUT_DIR/${sample}.vcf.gz"
    if [ ! -f "$VCF" ]; then
        lofreq call-parallel -f "$REF_FA" -o "$VCF" -m lofreq -C 50 -q 20 -Q 20 -t 4 "$OUT_DIR/${sample}.bam"
        tabix -p vcf "$VCF"
    fi
done

# 4. Collapsing
COLLAPSED="$OUT_DIR/collapsed.tsv"
if [ ! -f "$COLLAPSED" ]; then
    printf "sample\tchrom\tpos\tref\talt\taf\n" > "$COLLAPSED"
    for sample in "${SAMPLES[@]}"; do
        bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%AF\n' "$OUT_DIR/${sample}.vcf.gz" | \
        sed "s/^/${sample}\t/" >> "$COLLAPSED"
    done
fi