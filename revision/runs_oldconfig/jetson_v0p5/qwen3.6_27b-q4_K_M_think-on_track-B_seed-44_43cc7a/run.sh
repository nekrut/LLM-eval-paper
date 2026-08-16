#!/usr/bin/env bash
set -euo pipefail

THREADS=${THREADS:-4}

mkdir -p results

REF="data/ref/chrM.fa"

if [[ ! -f "${REF}.bwt" ]]; then
    bwa index "$REF"
fi

SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

for SAMPLE in "${SAMPLES[@]}"; do
    R1="data/raw/${SAMPLE}_1.fq.gz"
    R2="data/raw/${SAMPLE}_2.fq.gz"
    BAM="results/${SAMPLE}.bam"
    BAI="results/${SAMPLE}.bam.bai"
    VCF_GZ="results/${SAMPLE}.vcf.gz"
    VCF_TBI="results/${SAMPLE}.vcf.gz.tbi"

    if [[ -f "$BAM" && -f "$BAI" && -f "$VCF_GZ" && -f "$VCF_TBI" ]]; then
        continue
    fi

    bwa mem -t "$THREADS" "$REF" "$R1" "$R2" | samtools sort -@ "$THREADS" -o "$BAM"

    samtools index "$BAM"

    VCF_TMP="results/${SAMPLE}.vcf"
    lofreq call --call-indels -f "$REF" -o "$VCF_TMP" "$BAM"

    bcftools view -Oz -o "$VCF_GZ" "$VCF_TMP"
    bcftools index "$VCF_GZ"

    rm -f "$VCF_TMP"
done

{
    printf "sample\tchrom\tpos\tref\talt\taf\n"
    for SAMPLE in "${SAMPLES[@]}"; do
        VCF_GZ="results/${SAMPLE}.vcf.gz"
        if [[ -f "$VCF_GZ" ]]; then
            bcftools query -f '%CHROM\t%POS\t%REF\t%ALT[\t%AF]\n' "$VCF_GZ" | \
                awk -v sample="$SAMPLE" -F'\t' '{print sample"\t"$0}'
        fi
    done
} > results/collapsed.tsv