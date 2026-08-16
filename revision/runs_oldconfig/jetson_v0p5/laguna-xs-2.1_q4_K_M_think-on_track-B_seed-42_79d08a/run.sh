#!/usr/bin/env bash
set -euo pipefail

THREADS=${THREADS:-4}

mkdir -p results

# Index reference if needed (idempotent)
if [ ! -f data/ref/chrM.fa.bwt ]; then
    bwa index data/ref/chrM.fa
fi

samples=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

for sample in "${samples[@]}"; do
    # Check if all outputs exist (idempotency)
    if [ -f "results/${sample}.bam" ] && \
       [ -f "results/${sample}.bam.bai" ] && \
       [ -f "results/${sample}.vcf.gz" ] && \
       [ -f "results/${sample}.vcf.gz.tbi" ]; then
        continue
    fi

    # Map reads with bwa mem and pipe to samtools for sorting
    bwa mem -t "${THREADS}" data/ref/chrM.fa \
        <(zcat "data/raw/${sample}_1.fq.gz") \
        <(zcat "data/raw/${sample}_2.fq.gz") | \
        samtools view -bS - | \
        samtools sort -o "results/${sample}.bam" -

    # Index BAM file
    samtools index "results/${sample}.bam"

    # Call variants with lofreq and compress to VCF
    lofreq call -f data/ref/chrM.fa -r chrM "results/${sample}.bam" | \
        bcftools view -Oz -o "results/${sample}.vcf.gz" --threads "${THREADS}"

    # Index VCF file
    tabix "results/${sample}.vcf.gz"
done

# Create collapsed.tsv with all variants across samples
{
    printf 'sample\tchrom\tpos\tref\talt\taf\n'
    for sample in "${samples[@]}"; do
        if [ -f "results/${sample}.vcf.gz" ]; then
            bcftools query -f '%CHROM\t%POS\t%REF\t%ALT[\t%AF]\n' \
                "results/${sample}.vcf.gz" | \
                awk -v sample="${sample}" '{print sample"\t"$0}'
        fi
    done
} > results/collapsed.tsv