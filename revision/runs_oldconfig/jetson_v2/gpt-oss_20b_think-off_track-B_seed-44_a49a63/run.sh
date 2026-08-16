#!/usr/bin/env bash
set -euo pipefail

THREADS=4

# Ensure results directory exists
mkdir -p results

# Reference indexing (if not already indexed)
REF=data/ref/chrM.fa
if [ ! -f "${REF}.fai" ]; then
    bwa index "$REF"
    samtools faidx "$REF"
fi

# Sample list
samples=(M117-bl M117-ch M117C1-bl M117C1-ch)

# Process each sample
for sample in "${samples[@]}"; do
    fq1=data/raw/${sample}_1.fq.gz
    fq2=data/raw/${sample}_2.fq.gz
    bam=results/${sample}.bam
    bai=results/${sample}.bam.bai
    vcf=results/${sample}.vcf.gz
    tbi=results/${sample}.vcf.gz.tbi

    # Mapping (if BAM or BAI missing)
    if [ ! -f "$bam" ] || [ ! -f "$bai" ]; then
        bwa mem -t "$THREADS" "$REF" "$fq1" "$fq2" | \
            samtools view -Sb - | \
            samtools sort -@ "$THREADS" -o "$bam"
        samtools index "$bam"
    fi

    # Variant calling (if VCF or TBI missing)
    if [ ! -f "$vcf" ] || [ ! -f "$tbi" ]; then
        lofreq call -f "$REF" -b "$bam" | \
            bcftools view -Oz -o "$vcf" -
        tabix -p vcf "$vcf"
    fi
done

# Generate collapsed table if not present
collapsed=results/collapsed.tsv
if [ ! -f "$collapsed" ]; then
    printf "sample\tchrom\tpos\tref\talt\taf\n" > "$collapsed"
    for sample in "${samples[@]}"; do
        vcf=results/${sample}.vcf.gz
        bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t[%INFO/AF]\n" "$vcf" >> "$collapsed"
    done
fi

exit 0