#!/usr/bin/env bash
set -euo pipefail

RAW_DIR="data/raw"
REF_DIR="data/ref"
OUT_DIR="results"

mkdir -p "$OUT_DIR"

# 1. Index Reference Genome
REF_FA="$REF_DIR/chrM.fa"
if [ ! -f "$REF_FA.bwt" ]; then
    bwa index "$REF_FA"
    samtools faidx "$REF_FA"
fi

# 2. Process Each Sample
for sample in M117-bl M117-ch M117C1-bl M117C1-ch; do
    # Alignment
    BAM="$OUT_DIR/${sample}.bam"
    if [ ! -f "$BAM" ]; then
        bwa mem -t 4 "$REF_FA" "$RAW_DIR/${sample}_1.fq.gz" "$RAW_DIR/${sample}_2.fq.gz" | \
        samtools sort -@ 4 -o "$BAM"
        samtools index "$BAM"
    fi

    # Variant Calling
    VCF="$OUT_DIR/${sample}.vcf.gz"
    if [ ! -f "$VCF" ]; then
        lofreq call-parallel -f "$REF_FA" -o "$VCF" -m lofreq -C 20 -q 20 -t 4 "$BAM"
        tabix -p vcf "$VCF"
    fi
done

# 3. Collapse Results
COLLAPSED="$OUT_DIR/collapsed.tsv"
if [ ! -f "$COLLAPSED" ]; then
    bcftools query -f '%SAMPLE\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "$OUT_DIR"/*.vcf.gz | \
    sort -k1,1 -k2,2n -k3,3n > "$COLLAPSED"
fi