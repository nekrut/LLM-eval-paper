#!/usr/bin/env bash
set -euo pipefail

THREADS=4
mkdir -p results

# Index reference
if [ ! -f data/ref/chrM.fa.bwt ]; then
    bwa index data/ref/chrM.fa
fi

# Function to process a sample
process_sample() {
    local sample=$1
    local r1="data/raw/${sample}_1.fq.gz"
    local r2="data/raw/${sample}_2.fq.gz"
    local bam="results/${sample}.bam"
    local vcf="results/${sample}.vcf.gz"
    local tbi="results/${sample}.vcf.gz.tbi"

    # Check if outputs exist
    if [ -f "$bam" ] && [ -f "$bam.bai" ] && [ -f "$vcf" ] && [ -f "$tbi" ]; then
        return 0
    fi

    # Align
    bwa mem -t "$THREADS" data/ref/chrM.fa "$r1" "$r2" | \
        samtools view -b - > "$bam"

    # Sort and index
    samtools sort -@ "$THREADS" -o "${bam}.sorted" "$bam"
    samtools index "${bam}.sorted"
    mv "${bam}.sorted" "$bam"
    rm "${bam}.bai"
    mv "${bam}.sorted.bai" "$bam.bai"

    # Call variants
    lofreq call-parallel -f data/ref/chrM.fa -o "$vcf" -t "$THREADS" "$bam"

    # Index VCF
    tabix -p vcf "$vcf"
}

# Process all samples
process_sample "M117-bl"
process_sample "M117-ch"
process_sample "M117C1-bl"
process_sample "M117C1-ch"

# Collapse VCFs
bcftools concat -Oz -o results/collapsed.vcf.gz results/*.vcf.gz
tabix -p vcf results/collapsed.vcf.gz

# Convert to TSV and collapse
bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%AF\n' results/collapsed.vcf.gz | \
    awk '!seen[$1,$2,$3,$4,$5]++' > results/collapsed.tsv

exit 0