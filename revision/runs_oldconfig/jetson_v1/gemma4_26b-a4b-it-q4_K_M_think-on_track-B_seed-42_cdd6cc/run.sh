#!/usr/bin/env bash
set -euo pipefail

# Create output directory
mkdir -p results

# Reference indexing
if [[ ! -f "data/ref/chrM.fa.bwt" ]]; then
    bwa index data/ref/chrM.fa
fi

if [[ ! -f "data/ref/chrM.fa.fai" ]]; then
    samtools faidx data/ref/chrM.fa
fi

# Samples to process
samples=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

for s in "${samples[@]}"; do
    # Check if the final output for this sample already exists (idempotency)
    if [[ -f "results/${s}.vcf.gz" ]]; then
        continue
    fi

    # Alignment and sorting
    bwa mem -t 4 data/ref/chrM.fa \
        "data/raw/${s}_1.fq.gz" \
        "data/raw/${s}_2.fq.gz" | \
        samtools sort -@ 4 -o "results/${s}.bam"

    # Index BAM
    samtools index "results/${s}.bam"

    # Variant calling using lofreq
    lofreq call -f data/ref/chrM.fa -o "results/${s}.vcf" "results/${s}.bam"

    # Compress and index VCF
    bcftools view -Oz -o "results/${s}.vcf.gz" "results/${s}.vcf"
    tabix -p vcf "results/${s}.vcf.gz"

    # Cleanup intermediate uncompressed VCF
    rm -f "results/${s}.vcf"
done

# Generate collapsed table
echo -e "sample\tchrom\tpos\tref\talt\naf" > results/collapsed.tsv

for vcf in results/*.vcf.gz; do
    if [[ -f "$vcf" ]]; then
        s_name=$(basename "$vcf" .vcf.gz)
        # Extract variants and append to table
        # Using INFO/AF which is standard for lofreq output
        bcftools query -f "${s_name}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "$vcf" >> results/collapsed.tsv || true
    fi
done

exit 0