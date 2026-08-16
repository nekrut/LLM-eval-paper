#!/usr/bin/env bash
set -euo pipefail

THREADS=4
REF=data/ref/chrM.fa
RAW=data/raw
OUT=results

mkdir -p "$OUT"

# Index reference if missing
if [ ! -f "${REF}.bwt" ]; then
    bwa index "$REF"
    samtools faidx "$REF"
fi

# Process each sample
for SAMPLE in M117-bl M117-ch M117C1-bl M117C1-ch; do
    R1="${RAW}/${SAMPLE}_1.fq.gz"
    R2="${RAW}/${SAMPLE}_2.fq.gz"
    BAM="${OUT}/${SAMPLE}.bam"
    VCF="${OUT}/${SAMPLE}.vcf.gz"

    # Align reads
    if [ ! -f "$BAM" ]; then
        bwa mem -t "$THREADS" "$REF" "$R1" "$R2" | \
        samtools sort -o "$BAM" -
    fi

    # Index BAM
    if [ ! -f "${BAM}.bai" ]; then
        samtools index "$BAM"
    fi

    # Call variants (haploid for mtDNA)
    if [ ! -f "$VCF" ]; then
        lofreq call-parallel -f "$REF" -o "$VCF" -m lofreq -t "$THREADS" -p 1 "$BAM"
    fi

    # Index VCF
    if [ ! -f "${VCF}.tbi" ]; then
        tabix -p vcf "$VCF"
    fi
done

# Merge and collapse results
MERGED="${OUT}/merged.vcf.gz"
COLLAPSED="${OUT}/collapsed.tsv"

if [ ! -f "$COLLAPSED" ]; then
    bcftools merge -Oz -o "$MERGED" "${OUT}"/*.vcf.gz
    tabix -p vcf "$MERGED"
    bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\t%SAMPLE\n' "$MERGED" | \
        awk '{print $6"\t"$1"\t"$2"\t"$4"\t"$5"\t"$8}' > "$COLLAPSED"
    printf "sample\tchrom\tpos\tref\talt\taf\n" > "$COLLAPSED"
fi