#!/usr/bin/env bash
set -euo pipefail

mkdir -p results

REF="data/ref/chrM.fa"
THREADS=4

if [ ! -f "${REF}.bwt" ]; then
    bwa index "$REF"
fi

if [ ! -f "${REF}.fai" ]; then
    samtools faidx "$REF"
fi

SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

for SAMPLE in "${SAMPLES[@]}"; do
    BAM_OUT="results/${SAMPLE}.bam"
    VCF_OUT="results/${SAMPLE}.vcf.gz"

    if [ -f "$BAM_OUT" ] && [ -f "$VCF_OUT" ]; then
        continue
    fi

    R1="data/raw/${SAMPLE}_1.fq.gz"
    R2="data/raw/${SAMPLE}_2.fq.gz"

    bwa mem -t "$THREADS" "$REF" "$R1" "$R2" | \
    samtools view -@ "$THREADS" -Sb - | \
    samtools sort -@ "$THREADS" -o "$BAM_OUT"

    samtools index "$BAM_OUT"

    if [ ! -f "$VCF_OUT" ]; then
        lofreq call -f "$REF" -o "$VCF_OUT" "$BAM_OUT"
        tabix -p vcf "$VCF_OUT"
    fi
done

if [ ! -f "results/collapsed.tsv" ]; then
    printf "sample\tchrom\tpos\tref\talt\taf\n" > results/collapsed.tsv
    for SAMPLE in "${SAMPLES[@]}"; do
        VCF="results/${SAMPLE}.vcf.gz"
        if [ -f "$VCF" ]; then
            bcftools query -f "$SAMPLE\t%CHROM\t%POS\t%REF\t%ALT\t[%AF]\n" "$VCF" >> results/collapsed.tsv
        fi
    done
fi

exit 0