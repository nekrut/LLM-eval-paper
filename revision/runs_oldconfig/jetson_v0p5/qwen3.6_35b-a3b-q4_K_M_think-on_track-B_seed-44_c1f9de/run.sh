#!/usr/bin/env bash
set -euo pipefail

REF="data/ref/chrM.fa"
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

mkdir -p results

if [[ ! -f "${REF}.fai" ]]; then
    samtools faidx "$REF"
fi

for S in "${SAMPLES[@]}"; do
    BAM="results/${S}.bam"
    VCF="results/${S}.vcf.gz"

    if [[ ! -f "$BAM" ]]; then
        bwa mem -t 4 "$REF" "data/raw/${S}_1.fq.gz" "data/raw/${S}_2.fq.gz" | \
            samtools sort -@ 4 -o "$BAM" -
    fi

    if [[ ! -f "${BAM}.bai" ]]; then
        samtools index "$BAM"
    fi

    if [[ ! -f "$VCF" ]]; then
        bcftools mpileup -f "$REF" -Ou "$BAM" | \
            bcftools call -mv -Oz -o "$VCF"
    fi

    if [[ ! -f "${VCF}.tbi" ]]; then
        tabix -p vcf "$VCF"
    fi
done

COLLAPSED="results/collapsed.tsv"
if [[ ! -f "$COLLAPSED" ]]; then
    printf "sample\tchrom\tpos\tref\talt\taf\n" > "$COLLAPSED"
    for S in "${SAMPLES[@]}"; do
        VCF="results/${S}.vcf.gz"
        bcftools query -f "%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "$VCF" | \
            awk -v s="$S" 'NF {print s"\t"$0}' >> "$COLLAPSED"
    done
fi