#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

mkdir -p results

REF="data/ref/chrM.fa"
if [ ! -f "${REF}.fai" ] || [ ! -f "${REF}.amb" ]; then
    samtools faidx "$REF"
    bwa index "$REF"
fi

for s in "${SAMPLES[@]}"; do
    BAM="results/${s}.bam"
    BAI="results/${s}.bam.bai"
    VCF_GZ_TBI="results/${s}.vcf.gz.tbi"

    if [ -f "$BAM" ] && [ -f "$BAI" ] && [ -f "$VCF_GZ_TBI" ]; then
        continue
    fi

    bwa mem -t "$THREADS" \
        -R "@RG\\tID:${s}\\tSM:${s}\\tLB:${s}\\tPL:ILLUMINA" \
        data/raw/${s}_1.fq.gz data/raw/${s}_2.fq.gz | \
        samtools sort -@ "$THREADS" -o "$BAM"

    samtools index -@ "$THREADS" "$BAM"

    lofreq call-parallel --pp-threads "$THREADS" --verbose \
        --ref "$REF" --out results/${s}.vcf \
        --sig --bonf \
        "$BAM"

    bgzip -c results/${s}.vcf > results/${s}.vcf.gz
    rm results/${s}.vcf
    tabix -p vcf results/${s}.vcf.gz
done

COLLAPSED="results/collapsed.tsv"
if [ ! -f "$COLLAPSED" ]; then
    printf "sample\tchrom\tpos\tref\talt\taf\n" > "$COLLAPSED"
    for s in "${SAMPLES[@]}"; do
        bcftools query -f "${s}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" results/${s}.vcf.gz >> "$COLLAPSED"
    done
fi

exit 0