#!/usr/bin/env bash
set -euo pipefail

THREADS=4
mkdir -p results

# 1. Index Reference
if [ ! -f data/ref/chrM.fa.bwt ]; then
    bwa index data/ref/chrM.fa
    samtools faidx data/ref/chrM.fa
fi

# 2. Process Samples
samples=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

for sample in "${samples[@]}"; do
    # Check if outputs already exist
    if [ -f "results/${sample}.vcf.gz" ]; then
        continue
    fi

    # Align
    bwa mem -t "$THREADS" data/ref/chrM.fa data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz | \
    samtools view -b - | \
    samtools sort -@ "$THREADS" -o "results/${sample}.bam" -

    # Index BAM
    samtools index "results/${sample}.bam"

    # Call Variants (lofreq)
    lofreq call-parallel -f data/ref/chrM.fa -o "results/${sample}.vcf.gz" --ploidy 1 -m lofreq -C 20 -q 20 -Q 20 -t "$THREADS" "results/${sample}.bam"
done

# 3. Collapsing
if [ ! -f results/combined.vcf.gz ]; then
    bcftools concat -Oz -o results/combined.vcf.gz results/*.vcf.gz
    tabix -p vcf results/combined.vcf.gz
fi

# 4. Extract Columns
bcftools query -f '%SAMPLE\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' results/combined.vcf.gz > results/collapsed.tsv