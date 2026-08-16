#!/usr/bin/env bash
set -euo pipefail

mkdir -p results

if [[ ! -f "data/ref/chrM.fa.bwt" ]]; then
    bwa index data/ref/chrM.fa
fi

samples=()
for f in data/raw/*_1.fq.gz; do
    sample=$(basename "$f" _1.fq	gz)
    # Correcting the basename logic for potential trailing characters
    sample=$(basename "$f" _1.fq.gz)
    samples+=("$sample")
done

for s in "${samples[@]}"; do
    BAM="results/${s}.bam"
    VCF_GZ="results/${s}.vcf.gz"

    if [[ ! -f "$BAM" ]]; then
        bwa mem -t 4 data/ref/chrM.fa "data/raw/${s}_1.fq.gz" "data/raw/${s}_2.fq.gz" | \
        samtools view -uB - | \
        samtools sort -@ 4 -o "$BAM" -
        samtools index "$BAM"
    fi

    if [[ ! -f "$VCF_GZ" ]]; then
        VCF_TMP="results/${s}_tmp.vcf"
        lofreq call -f data/ref/chrM.fa -o "$VCF_TMP" "$BAM"
        bgzip -c "$VCF_TMP" > "$VCF_GZ"
        rm "$VCF_TMP"
        tabix -p vcf "$VCF_GZ"
    fi
done

printf "sample\tchrom\tpos\tref\talt\taf\n" > results/collapsed.tsv
for s in "${samples[@]}"; do
    VCF_GZ="results/${s}.vcf.gz"
    if [[ -f "$VCF_GZ" ]]; then
        bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "$VCF_GZ" | \
        awk -v sample="$s" '{print sample "\t" $0}' >> results/collapsed.tsv
    fi
done