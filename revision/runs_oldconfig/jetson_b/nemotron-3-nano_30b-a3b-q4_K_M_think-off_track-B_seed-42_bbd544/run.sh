#!/usr/bin/env bash
set -euo pipefail

mkdir -p results

# Index reference if not already indexed
if [ ! -f data/ref/chrM.fa.bwt ]; then
    bwa index data/ref/chrM.fa
fi

# Function to process a sample
process_sample() {
    local base=$1
    local r1="data/raw/${base}_1.fq.gz"
    local r2="data/raw/${base}_2.fq.gz"
    local out_prefix="results/${base}"

    # Skip if all outputs exist
    [ -f "${out_prefix}.bam" ] && [ -f "${out_prefix}.bam.bai" ] && [ -f "${out_prefix}.vcf.gz" ] && exit 0

    # Align with BWA-MEM
    bwa mem -t 4 data/ref/chrM.fa "$r1" "$r2" | samtools view -@ 2 -b - > "${out_prefix}.bam"

    # Sort and index
    samtools sort -o "${out_prefix}.sorted.bam" "${out_prefix}.bam"
    samtools index "${out_prefix}.sorted.bam"

    # Generate VCF with lofreq
    lofreq variant -f data/ref/chrM.fa -b "${out_prefix}.sorted.bam" -t 0.01 --min-alternative-count 2 \
        | bcftools view -Oz -o "${out_prefix}.vcf.gz"

    # Index VCF
    tabix -p vcf "${out_prefix}.vcf.gz"

    # Collapse table generation will be done later in a separate step after all samples are processed
}

# Process each sample
process_sample "M117-bl"
process_sample "M117-ch"
process_sample "M117C1-bl"
process_sample "M117C1-ch"

# Generate collapsed.tsv with header and per-sample rows
{
    echo -e "sample\tchrom\tpos\tref\talt\taf"
    for sample in M117-bl M117-ch M117C1-bl M117C1-ch; do
        base="${sample}"
        vcf_file="results/${base}.vcf.gz"
        if [ -f "${vcf_file}" ]; then
            tabix -p vcf "${vcf_file}" | \
                awk -F'\t' '{print "'"${sample}"'" "\t" $1 "\t" $2 "\t" $4 "\t" $5 "\t" 0}' >> collapsed.tsv.tmp
        fi
    done
    cat collapsed.tsv.tmp > results/collapsed.tsv
    rm -f collapsed.tsv.tmp
} && mv collapsed.tsv.tmp results/collapsed.tsv

# Ensure all outputs are present
for sample in M117-bl M117-ch M117C1-bl M117C1-ch; do
    base="${sample}"
    [ -f "results/${base}.bam" ] || exit 1
    [ -f "results/${base}.bam.bai" ] || exit 1
    [ -f "results/${base}.vcf.gz" ] || exit 1
    [ -f "results/${base}.vcf.gz.tbi" ] || tabix -p vcf "results/${base}.vcf.gz"
done

exit 0