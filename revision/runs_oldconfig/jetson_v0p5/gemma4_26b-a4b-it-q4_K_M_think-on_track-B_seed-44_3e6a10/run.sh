#!/usr/bin/env bash
set -euo pipefail

mkdir -p results

# Index reference if not already indexed
if [[ ! -f "data/ref/chrM.fa.bwt" ]]; then
    bwa index data/ref/chrM.fa
fi

if [[ ! -f "data/ref/chrM.fa.fai" ]]; then
    samtools faidx data/ref/chrM.fa
fi

SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

for sample in "${SAMPLES[@]}"; do
    # Check if the final VCF exists to ensure idempotency
    if [[ ! -f "results/${sample}.vcf.gz" ]]; then
        # Alignment and sorting
        bwa mem -t 4 data/ref/chrM.fa \
            data/raw/"${sample}_1.fq.gz" \
            data/raw/"${sample}_2.fq.gz" | \
        samtools sort -@ 4 -o "results/${sample}.bam" -

        # Index BAM
        samtools index "results/${sample}.bam"

        # Variant calling with lofreq
        # lofreq call produces a plain VCF; we convert to compressed bgzip format
        lofreq call -f data/ref/chrM.fa -o "results/${sample}.vcf" "results/${sample}.bam"
        bcftools view -Oz -o "results/${sample}.vcf.gz" "results/${sample}.vcf"
        tabix -p vcf "results/${sample}.vcf.gz"

        # Cleanup intermediate uncompressed VCF
        rm "results/${sample}.vcf"
    fi
done

# Create the collapsed table
printf "sample\tchrom\tpos\tref\talt\taf\n" > results/collapsed.tsv

for sample in "${SAMPLES[@]}"; do
    if [[ -f "results/${sample}.vcf.gz" ]]; then
        # Extract variants and append to the table
        # Using %INFO/AF as lofreq stores allele frequency in the INFO field
        bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "results/${sample}.vcf.gz" >> results/collapsed.tsv
    fi
done

exit 0