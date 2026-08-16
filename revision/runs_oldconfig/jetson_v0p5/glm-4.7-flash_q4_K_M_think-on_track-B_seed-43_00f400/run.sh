#!/usr/bin/env bash
set -euo pipefail

THREADS=4
RAW="data/raw"
REF="data/ref"
OUT="results"

mkdir -p "$OUT"

# Index reference
if [ ! -f "${REF}/chrM.fa.bwt" ]; then
    bwa index "${REF}/chrM.fa"
fi

# Process samples
for SAMPLE in M117-bl M117-ch M117C1-bl M117C1-ch; do
    # BAM
    if [ ! -f "${OUT}/${SAMPLE}.bam" ]; then
        bwa mem -t "$THREADS" "${REF}/chrM.fa" \
            "${RAW}/${SAMPLE}_1.fq.gz" "${RAW}/${SAMPLE}_2.fq.gz" \
            | samtools sort -@ "$THREADS" -o "${OUT}/${SAMPLE}.sorted.bam" -
        samtools index "${OUT}/${SAMPLE}.sorted.bam"
    fi

    # VCF
    if [ ! -f "${OUT}/${SAMPLE}.vcf.gz" ]; then
        lofreq call-parallel -f "${REF}/chrM.fa" -o "${OUT}/${SAMPLE}.vcf.gz" \
            "${OUT}/${SAMPLE}.sorted.bam" -t "$THREADS"
        bcftools sort -o "${OUT}/${SAMPLE}.sorted.vcf.gz" "${OUT}/${SAMPLE}.vcf.gz"
        tabix -p vcf "${OUT}/${SAMPLE}.sorted.vcf.gz"
    fi
done

# Collapsing
bcftools merge -Oz -o "${OUT}/merged.vcf.gz" "${OUT}"/*.sorted.vcf.gz
tabix -p vcf "${OUT}/merged.vcf.gz"

printf "sample\tchrom\tpos\tref\talt\taf\n" > "${OUT}/collapsed.tsv"
bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%AF\t%SAMPLE\n' "${OUT}/merged.vcf.gz" \
    | awk '!seen[$1,$2,$3,$4]++ {print $1,$2,$3,$4,$5,$6}' >> "${OUT}/collapsed.tsv"