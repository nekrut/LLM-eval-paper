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
    BAM="results/${s}.bam"
    VCF="results/${s}.vcf.gz"
    F1="data/raw/${s}_1.fq.gz"
    F2="data/raw/${s}_2.fq.gz"

    if [[ ! -f "$BAM" ]]; then
        bwa mem -t 4 "$REF" "$F1" "$F2" | \
        samtools sort -@ 4 -o "$BAM"
        samtools index "$BAM"
    fi

    if [[ ! -f "$VCF" ]]; then
        # lofreq call produces a plain VCF; we compress it using bcftools
        TEMP_VCF="results/${s}_tmp.vcf"
        lofreq call -f "$REF" -o "$TEMP_VCF" "$BAM"
        bcftools view -Oz -o "$VCF" "$TEMP_VCF"
        bcftools index -t "$VCF"
        rm -f "$TEMP_VCF"
    fi
done

echo -e "sample\tchrom\tpos\tref\talt\taf" > results/collapsed.tsv
for s in "${SAMPLES[@]}"; do
    VCF="results/${s}.vcf.gz"
    if [[ -f "$VCF" ]]; then
        bcftools query -f "%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "$VCF" | \
        awk -v sample="$s" '{print sample "\t" $0}' >> results/collapsed.tsv
    fi
done