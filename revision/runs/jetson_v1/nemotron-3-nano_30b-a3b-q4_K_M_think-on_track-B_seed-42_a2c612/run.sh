#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)

mkdir -p results

# Idempotency check: exit if all expected outputs already exist
required=(
    "results/M117-bl.bam"
    "results/M117-bl.bai"
    "results/M117-bl.vcf.gz"
    "results/M117-bl.vcf.gz.tbi"
    "results/M117-ch.bam"
    "results/M117-ch.bai"
    "results/M117-ch.vcf.gz"
    "results/M117-ch.vcf.gz.tbi"
    "results/M117C1-bl.bam"
    "results/M117C1-bl.bai"
    "results/M117C1-bl.vcf.gz"
    "results/M117C1-bl.vcf.gz.tbi"
    "results/M117C1-ch.bam"
    "results/M117C1-ch.bai"
    "results/M117C1-ch.vcf.gz"
    "results/M117C1-ch.vcf.gz.tbi"
    "results/collapsed.tsv"
)
all_present=1
for f in "${required[@]}"; do
    if [[ ! -e "$f" ]]; then
        all_present=0
        break
    fi
done
if (( all_present )); then
    exit 0
fi

# Process each sample
for sample in "${SAMPLES[@]}"; do
    r1="data/raw/${sample}_1.fq.gz"
    r2="data/raw/${sample}_2.fq.gz"

    # Align if BAM not present
    if [[ ! -e "results/${sample}.bam" ]]; then
        bwa mem -t "$THREADS" data/ref/chrM.fa "$r1" "$r2" | samtools view -@ "$THREADS" -b - > "results/${sample}.bam"
        samtools index "results/${sample}.bam"
    fi

    # Variant calling if VCF not present
    if [[ ! -e "results/${sample}.vcf.gz" ]]; then
        samtools mpileup -f data/ref/chrM.fa -Ou "results/${sample}.bam" | \
            bcftools call -mv -Oz -o "results/${sample}.vcf.gz"
        tabix -p vcf "results/${sample}.vcf.gz"
    fi
done

# Generate collapsed.tsv if missing
if [[ ! -e "results/collapsed.tsv" ]]; then
    printf "sample\tchrom\tpos\tref\talt\taf\n" > results/collapsed.tsv
    for sample in "${SAMPLES[@]}"; do
        bcftools query -f '%CHROM\t%POS\t%REF\t%ALT[\t%AF]\n' "results/${sample}.vcf.gz" |
        while IFS=$'\t' read -r chrom pos ref alt af; do
            printf "%s\t%s\t%s\t%s\t%s\t%s\n" "$sample" "$chrom" "$pos" "$ref" "$alt" "$af"
        done >> results/collapsed.tsv
    done
fi