#!/usr/bin/env bash
set -euo pipefail

mkdir -p results

REF="data/ref/chrM.fa"
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
THREADS=4

if [ ! -f "${REF}.bwt" ]; then
    bwa index "$REF"
fi

if [ ! -f "${REF}.fai" ]; then
    samtools faidx "$REF"
fi

for SAMPLE in "${SAMPLES[@]}"; do
    BAM="results/${SAMPLE}.bam"
    VCF="results/${SAMPLE}.vcf.gz"

    if [[ -f "$BAM" && -f "$BAM.bai" && -f "$VCF" && -f "$VCF.tbi" ]]; then
        continue
    fi

    R1="data/raw/${SAMPLE}_1.fq.gz"
    R2="data/raw/${SAMPLE}_2.fq.gz"

    bwa mem -t "$THREADS" "$REF" "$R1" "$R2" | \
    samtools view -@ "$THREADS" -bS - | \
    samtools sort -@ "$THREADS" -o "$BAM"

    samtools index "$BAM"

    if [[ ! -f "$VCF" ]]; then
        lofreq call --region chrM:1-16569 -f "$REF" -o "$VCF" "$BAM"
        tabix "$VCF"
    fi
done

if [[ ! -f "results/collapsed.tsv" ]]; then
    printf "sample\tchrom\tpos\tref\talt\taf\n" > results/collapsed.tsv
    for SAMPLE in "${SAMPLES[@]}"; do
        VCF="results/${SAMPLE}.vcf.gz"
        if [[ -f "$VCF" ]]; then
            bcftools query -f "$SAMPLE\t%CHROM\t%POS\t%REF\t%ALT\t[%AF]\n" "$VCF" >> results/collapsed.tsv
        fi
    done
fi

exit 0