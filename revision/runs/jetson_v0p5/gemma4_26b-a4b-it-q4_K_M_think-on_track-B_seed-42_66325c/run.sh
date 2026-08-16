#!/usr/bin/env bash
set -euo pipefail

mkdir -p results

REF="data/ref/chrM.fa"
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

if [[ ! -f "${REF}.bwt" ]]; then
    bwa index "$REF"
fi

if [[ ! -f "${REF}.fai" ]]; then
    samtools faidx "$REF"
fi

for s in "${SAMPLES[@]}"; do
    VCF_GZ="results/${s}.vcf.gz"
    BAM="results/${s}.bam"

    if [[ ! -f "$VCF_GZ" ]]; then
        bwa mem -t 4 "$REF" "data/raw/${s}_1.fq.gz" "data/raw/${s}_2.fq.gz" | \
            samtools sort -@ 4 -o "$BAM" -
        samtools index "$BAM"

        lofreq call -f "$REF" -p "$BAM" > "results/${s}.vcf"
        bgzip -c "results/${s}.vcf" > "$VCF_GZ"
        tabix -p vcf "$VCF_GZ"
        rm "results/${s}.vcf"
    fi
done

if [[ ! -f "results/collapsed.tsv" ]]; then
    printf "sample\tchrom\tpos\tref\talt\taf\n" > results/collapsed.tsv
    for s in "${SAMPLES[@]}"; do
        VCF_GZ="results/${s}.vcf.gz"
        if [[ -f "$VCF_GZ" ]]; then
            bcftools query -f "$s\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "$VCF_GZ" >> results/collapsed.tsv
        fi
    done
fi

exit 0