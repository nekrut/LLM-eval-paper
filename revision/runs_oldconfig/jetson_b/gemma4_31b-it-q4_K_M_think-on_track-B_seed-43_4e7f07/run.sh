#!/usr/bin/env bash
set -euo pipefail

SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
REF="data/ref/chrM.fa"
OUTDIR="results"

mkdir -p "$OUTDIR"

if [[ ! -f ${REF}.bwt ]]; then
    bwa index "$REF"
fi

if [[ ! -f ${REF}.fai ]]; then
    samtools faidx "$REF"
fi

for s in "${SAMPLES[@]}"; do
    BAM="$OUTDIR/${s}.bam"
    VCF_GZ="$OUTDIR/${s}.vcf.gz"

    if [[ ! -f "$BAM" ]]; then
        bwa mem -t 4 "$REF" "data/raw/${s}_1.fq.gz" "data/raw/${s}_2.fq.gz" | \
        samtools view -Sb - | \
        samtools sort -o "$BAM"
    fi

    if [[ ! -f ${BAM}.bai ]]; then
        samtools index "$BAM"
    fi

    if [[ ! -f "$VCF_GZ" ]]; then
        lofreq call -f "$REF" -b "$BAM" > "${BAM}.vcf"
        bcftools view -Oz -o "$VCF_GZ" "${BAM}.vcf"
        rm "${BAM}.vcf"
    fi

    if [[ ! -f ${VCF_GZ}.tbi ]]; then
        tabix -p vcf "$VCF_GZ"
    fi
done

COLLAPSED="$OUTDIR/collapsed.tsv"
if [[ ! -f "$COLLAPSED" ]]; then
    printf "sample\tchrom\tpos\tref\talt\taf\n" > "$COLLAPSED"
    for s in "${SAMPLES[@]}"; do
        bcftools query -f "${s}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "$OUTDIR/${s}.vcf.gz" >> "$COLLAPSED"
    done
fi