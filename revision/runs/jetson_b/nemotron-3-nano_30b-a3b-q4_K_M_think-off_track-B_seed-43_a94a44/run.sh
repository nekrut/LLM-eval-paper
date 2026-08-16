#!/usr/bin/env bash
set -euo pipefail

mkdir -p results

# Index reference if not already indexed
if [ ! -f data/ref/chrM.fa.bwt ]; then
    bwa index data/ref/chrM.fa
fi

declare -A samples=(
    ["M117-bl"]="data/raw/M117-bl_1.fq.gz data/raw/M117-bl_2.fq.gz"
    ["M117-ch"]="data/raw/M117-ch_1.fq.gz data/raw/M117-ch_2.fq.gz"
    ["M117C1-bl"]="data/raw/M117C1-bl_1.fq.gz data/raw/M117C1-bl_2.fq.gz"
    ["M117C1-ch"]="data/raw/M117C1-ch_1.fq.gz data/raw/M117C1-ch_2.fq.gz"
)

for sample in "${!samples[@]}"; do
    read -r r1 r2 <<< "${samples[$sample]}"

    # Skip if BAM already exists (idempotent)
    if [ -f "results/${sample}.bam" ]; then
        continue
    fi

    bwa mem -t 4 data/ref/chrM.fa "$r1" "$r2" | samtools view -@ 4 -b - > "results/${sample}.bam"
    samtools index "results/${sample}.bam"

    # Skip VCF if already exists
    if [ -f "results/${sample}.vcf.gz" ]; then
        continue
    fi

    bcftools mpileup -f data/ref/chrM.fa -R <(echo "-chrM:1-16569") \
        --min-MQ 20 --annot-coverage DP --annot-base-quality BQ \
        --annot-map-quality MQ --annot-read-depth AD \
        results/${sample}.bam | \
    bcftools call -c -Oz -o "results/${sample}.vcf.gz"

    tabix -p vcf "results/${sample}.vcf.gz"
done

# Collapsed.tsv: sample, chrom, pos, ref, alt, af
{
    echo -e "sample\tchrom\tpos\tref\talt\taf"
    for sample in "${!samples[@]}"; do
        bcftools query -f '%CHROM %POS %REF %ALT [ADF]\n' \
            results/${sample}.vcf.gz | \
        awk -v s="$sample" '
            BEGIN{OFS="\t"}
            {
                # ADF: allele depth for REF, ALT1, ALT2...
                split($5, adf, ",")
                ref_depth = adf[1]
                alt_depths = 0
                total_alt_depth = 0
                for (i=2; i<=length(adf); i++) {
                    total_alt_depth += adf[i]
                }
                af = (total_alt_depth > 0) ? total_alt_depth / (ref_depth + total_alt_depth) : "0"
                # Output each ALT allele separately
                split($4, alts, ",")
                for (i in alts) {
                    print s, $1, $2, $3, alts[i], af
                }
            }'
    done
} > results/collapsed.tsv

# Ensure collapsed.tsv is tab-separated and has header
if [ ! -s results/collapsed.tsv ]; then
    echo -e "sample\tchrom\tpos\tref\talt\taf" > results/collapsed.tsv
fi