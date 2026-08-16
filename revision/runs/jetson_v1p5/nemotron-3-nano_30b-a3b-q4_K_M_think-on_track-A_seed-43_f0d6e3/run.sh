#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
mkdir -p results

# Idempotency check: if collapsed.tsv exists and is non‑empty, exit immediately
if [[ -s results/collapsed.tsv ]]; then
    exit 0
fi

# Index reference files once if they are not already present
if [[ ! -f data/ref/chrM.fa.bwt ]]; then
    bwa index data/ref/chrM.fa
    samtools faidx data/ref/chrM.fa
fi

for sample in "${SAMPLES[@]}"; do
    # ----- Alignment & sorting (skip if BAM already exists) -----
    if [[ ! -f results/${sample}.bam ]]; then
        bwa mem -t "$THREADS" -R "@RG"$'\t'ID:${sample}$'\t'SM:${sample}$'\t'LB:${sample}$'\t'PL:ILLUMINA" data/ref/chrM.fa \
            data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz | \
            samtools sort -@ "$THREADS" -o results/${sample}.bam -
    fi

    # ----- BAM indexing (skip if index exists) -----
    if [[ ! -f results/${sample}.bam.bai ]]; then
        samtools index -@ "$THREADS" results/${sample}.bam
    fi

    # ----- Variant calling with LoFreq and compression (skip if .vcf.gz exists) -----
    if [[ ! -f results/${sample}.vcf.gz ]]; then
        lofreq call-parallel --pp-threads "$THREADS" -f data/ref/chrM.fa -o results/${sample}.vcf results/${sample}.bam
        bcftools view -Oz -o results/${sample}.vcf.gz results/${sample}.vcf
        tabix -p vcf results/${sample}.vcf.gz
    fi

    # ----- Append to collapsed.tsv (write header once, then sample lines) -----
    if [[ ! -s results/collapsed.tsv ]]; then
        printf 'sample\tchrom\tpos\tref\talt\taf\n' > results/collapsed.tsv
    fi
    while IFS= read -r line; do
        printf '%s\t%s\n' "$sample" "$line"
    done < <(bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' results/${sample}.vcf.gz) >> results/collapsed.tsv
done