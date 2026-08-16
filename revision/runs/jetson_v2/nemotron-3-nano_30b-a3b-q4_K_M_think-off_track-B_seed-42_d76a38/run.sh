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

    # Skip if BAM already exists (idempotent)
    if [ -f "${out_prefix}.bam" ]; then
        return 0
    fi

    # Align with bwa mem, sort and index with samtools
    bwa mem -t 4 data/ref/chrM.fa "$r1" "$r2" |
        samtools view -@ 4 -b - > "${out_prefix}.bam"
    samtools sort -o "${out_prefix}.sorted.bam" "${out_prefix}.bam"
    samtools index "${out_prefix}.sorted.bam"

    # Generate VCF with lofreq
    lofreq variant -f data/ref/chrM.fa \
        --min-qual 30 \
        --min-reads 10 \
        --min-alternative-reads 5 \
        --min-ALT-depth 5 \
        --bam "${out_prefix}.sorted.bam" \
        --output "${out_prefix}.vcf"

    # Compress and index VCF
    bgzip -@ 4 "${out_prefix}.vcf"
    tabix -p vcf "${out_prefix}.vcf.gz"

    # Extract fields with bcftools + SnpSift for collapsed.tsv later
    bcftools query -f '%CHROM\t%POS0\t%REF\t%ALT[\t%AF]\n' \
        "${out_prefix}.vcf.gz" > "${out_prefix}.bcf_fields"
}

# Process each sample in parallel (max 4 threads total)
samples=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
for s in "${samples[@]}"; do
    process_sample "$s" &
done

wait

# Build collapsed.tsv from all per-sample VCF fields
{
    echo -e "sample\tchrom\tpos\tref\talt\taf"
    for f in results/*.bcf_fields; do
        sample=$(basename "$f")
        while IFS=$'\t' read -r chrom pos ref alt af; do
            printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$sample" "$chrom" "$pos" "$ref" "$alt" "$af"
        done < "$f"
    done
} > results/collapsed.tsv

# Index collapsed.tsv with tabix (optional, not required by spec)
tabix -p vcf results/collapsed.tsv || true  # ignore if fails; not used downstream

exit 0