#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)

# Create results directory
mkdir -p results

# Reference indexing (once)
REF=data/ref/chrM.fa
if [ ! -f "${REF}.fai" ]; then
    samtools faidx "$REF"
fi
if [ ! -f "${REF}.amb" ]; then
    bwa index "$REF"
fi

# Per-sample processing
for sample in "${SAMPLES[@]}"; do
    BAM=results/${sample}.bam
    BAI=results/${sample}.bam.bai
    VCF=results/${sample}.vcf
    VCFZ=results/${sample}.vcf.gz
    TBIVCF=${VCFZ}.tbi

    # Alignment: run if BAM missing or older than any FASTQ
    if [ ! -f "$BAM" ] || \
       { [ "$(stat -c %Y data/raw/${sample}_1.fq.gz)" -gt "$(stat -c %Y "$BAM")" ] || \
         [ "$(stat -c %Y data/raw/${sample}_2.fq.gz)" -gt "$(stat -c %Y "$BAM")" ]; }; then
        bwa mem -t "$THREADS" -R "@RG\\tID:${sample}\\tSM:${sample}\\tLB:${sample}\\tPL:ILLUMINA" \
            data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz | \
            samtools sort -@ "$THREADS" -o "$BAM"
    fi

    # BAM indexing
    if [ ! -f "$BAI" ] || [ "$(stat -c %Y "$BAI")" -lt "$(stat -c %Y "$BAM")" ]; then
        samtools index -@ "$THREADS" "$BAM"
    fi

    # Variant calling: run if compressed VCF missing or older than BAM
    if [ ! -f "$TBIVCF" ] || [ "$(stat -c %Y "$TBIVCF")" -lt "$(stat -c %Y "$BAM")" ]; then
        lofreq call-parallel --pp-threads "$THREADS" -f "$REF" -b "$BAM" -o "$VCF"
        bcftools view -Oz -o "$VCFZ" "$VCF"
        tabix -p vcf "$VCFZ"
        rm -f "$VCF"
    fi
done

# Collapse step: rebuild if any VCF newer than collapsed.tsv or file missing
COLLAPSED=results/collapsed.tsv
REBUILD=false
if [ ! -f "$COLLAPSED" ]; then
    REBUILD=true
else
    for sample in "${SAMPLES[@]}"; do
        VCFZ=results/${sample}.vcf.gz
        if [ "$(stat -c %Y "$VCFZ")" -gt "$(stat -c %Y "$COLLAPSED")" ]; then
            REBUILD=true
            break
        fi
    done
fi

if $REBUILD; then
    >"$COLLAPSED"
    printf "sample\tchrom\tpos\tref\talt\taf\n" >> "$COLLAPSED"
    for sample in "${SAMPLES[@]}"; do
        VCFZ=results/${sample}.vcf.gz
        bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "$VCFZ" >> "$COLLAPSED"
    done
fi

exit 0