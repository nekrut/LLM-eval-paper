#!/usr/bin/env bash
set -euo pipefail

REF="data/ref/chrM.fa"
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

mkdir -p results

if [[ ! -f "$REF.fai" ]]; then
    samtools faidx "$REF"
fi

for S in "${SAMPLES[@]}"; do
    R1="data/raw/${S}_1.fq.gz"
    R2="data/raw/${S}_2.fq.gz"
    BAM="results/${S}.bam"
    BAI="${BAM}.bai"
    VCF="results/${S}.vcf.gz"
    TBI="${VCF}.tbi"

    if [[ -f "$BAM" && -f "$BAI" && -f "$VCF" && -f "$TBI" ]]; then
        continue
    fi

    bwa mem -t 4 "$REF" "$R1" "$R2" | samtools sort -@ 4 -o "$BAM" -
    samtools index "$BAM"

    bcftools mpileup -f "$REF" "$BAM" | bcftools call -mv -Oz -o "$VCF"
    bcftools index "$VCF"
done

printf "sample\tchrom\tpos\tref\talt\taf\n" > results/collapsed.tsv
for S in "${SAMPLES[@]}"; do
    VCF="results/${S}.vcf.gz"
    if [[ -f "$VCF" ]]; then
        bcftools query -f "%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "$VCF" | awk -v s="$S" '{print s"\t"$0}' >> results/collapsed.tsv
    fi
done