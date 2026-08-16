#!/usr/bin/env bash
set -euo pipefail

THREADS=4
RAW=data/raw
REF=data/ref
OUT=results

mkdir -p "$OUT"

# Index reference genome
bwa index "$REF/chrM.fa"
samtools faidx "$REF/chrM.fa"

# Process each sample
for SAMPLE in M117-bl M117-ch M117C1-bl M117C1-ch; do
    BAM="$OUT/${SAMPLE}.bam"
    VCF="$OUT/${SAMPLE}.vcf.gz"

    # Skip if BAM already exists (idempotency)
    if [ -f "$BAM" ]; then
        continue
    fi

    # Align reads
    bwa mem -t "$THREADS" "$REF/chrM.fa" "$RAW/${SAMPLE}_1.fq.gz" "$RAW/${SAMPLE}_2.fq.gz" \
        | samtools view -b - \
        | samtools sort -@ "$THREADS" -o "$BAM" -

    # Index BAM
    samtools index "$BAM"

    # Call variants
    lofreq call-parallel -f "$REF/chrM.fa" -o "$VCF" -m lofreq -O z -p "$THREADS" "$BAM"

    # Index VCF
    tabix -p vcf "$VCF"
done

# Collapse VCFs into a single table
if [ ! -f "$OUT/collapsed.tsv" ]; then
    bcftools concat -O z -o "$OUT/temp_combined.vcf.gz" "$OUT"/*.vcf.gz
    bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%AF\t%SAMPLE\n' "$OUT/temp_combined.vcf.gz" > "$OUT/collapsed.tsv"
    rm "$OUT/temp_combined.vcf.gz"
fi