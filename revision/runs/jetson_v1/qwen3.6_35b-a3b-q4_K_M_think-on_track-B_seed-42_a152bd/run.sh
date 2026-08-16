#!/usr/bin/env bash
set -euo pipefail

REF="data/ref/chrM.fa"
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

mkdir -p results

if [[ ! -f "$REF.fai" ]]; then
    samtools faidx "$REF"
fi
if [[ ! -f "${REF}.bwt" ]]; then
    bwa index "$REF"
fi

for smp in "${SAMPLES[@]}"; do
    if [[ ! -f "results/${smp}.bam" ]]; then
        bwa mem -t 4 "$REF" \
            "data/raw/${smp}_1.fq.gz" \
            "data/raw/${smp}_2.fq.gz" | \
        samtools sort -@ 4 -o "results/${smp}.bam" -
    fi

    if [[ ! -f "results/${smp}.bam.bai" ]]; then
        samtools index "results/${smp}.bam"
    fi

    if [[ ! -f "results/${smp}.vcf.gz" ]]; then
        bcftools mpileup -f "$REF" "results/${smp}.bam" | \
        bcftools call -mv -O z -o "results/${smp}.vcf.gz"
    fi

    if [[ ! -f "results/${smp}.vcf.gz.tbi" ]]; then
        bcftools index "results/${smp}.vcf.gz"
    fi
done

printf 'sample\tchrom\tpos\tref\talt\taf\n' > results/collapsed.tsv
for smp in "${SAMPLES[@]}"; do
    if [[ -f "results/${smp}.vcf.gz" ]]; then
        bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' \
            "results/${smp}.vcf.gz" | \
        awk -v s="$smp" '{print s"\t"$0}' >> results/collapsed.tsv
    fi
done