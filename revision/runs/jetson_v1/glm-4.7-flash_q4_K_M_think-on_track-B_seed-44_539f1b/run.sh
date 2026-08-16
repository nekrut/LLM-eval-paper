#!/usr/bin/env bash
set -euo pipefail

THREADS=4
RAW="data/raw"
REF="data/ref"
OUT="results"

mkdir -p "$OUT"

# Index reference (BWA and Samtools)
if [ ! -f "${REF}/chrM.fa.bwt" ]; then
    bwa index "${REF}/chrM.fa"
fi
if [ ! -f "${REF}/chrM.fa.fai" ]; then
    samtools faidx "${REF}/chrM.fa"
fi

# Process each sample
for sample in M117-bl M117-ch M117C1-bl M117C1-ch; do
    # Check for BAM and VCF existence for idempotency
    if [ -f "${OUT}/${sample}.bam" ] && [ -f "${OUT}/${sample}.vcf.gz" ]; then
        continue
    fi

    # Alignment
    bwa mem -t "$THREADS" "${REF}/chrM.fa" "${RAW}/${sample}_1.fq.gz" "${RAW}/${sample}_2.fq.gz" \
        | samtools view -b - \
        | samtools sort -o "${OUT}/${sample}.bam"
    samtools index "${OUT}/${sample}.bam"

    # Variant Calling
    lofreq call-parallel -f "${REF}/chrM.fa" -o "${OUT}/${sample}.vcf.gz" "${OUT}/${sample}.bam" -m lofreq -t "$THREADS"
    tabix -p vcf "${OUT}/${sample}.vcf.gz"
done

# Collapsing VCFs
if [ ! -f "${OUT}/collapsed.tsv" ]; then
    bcftools query -f '%SAMPLE\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "${OUT}"/*.vcf.gz > "${OUT}/collapsed.tsv"
fi