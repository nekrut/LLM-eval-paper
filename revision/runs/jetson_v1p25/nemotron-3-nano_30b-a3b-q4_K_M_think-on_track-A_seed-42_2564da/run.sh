#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)

mkdir -p results

# Reference indexing (once)
if [[ ! -f data/ref/chrM.fa.fai ]]; then
    samtools faidx data/ref/chrM.fa
    bwa index data/ref/chrM.fa
fi

# Per-sample processing
for sample in "${SAMPLES[@]}"; do
    # Skip if final TBI already exists
    if [[ -f results/${sample}.vcf.gz.tbi ]]; then
        continue
    fi

    # Align and sort to BAM (if not present)
    if [[ ! -f results/${sample}.bam ]]; then
        fq1=data/raw/${sample}_1.fq.gz
        fq2=data/raw/${sample}_2.fq.gz
        bwa mem -t 4 -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" data/ref/chrM.fa "$fq1" "$fq2" |
            samtools sort -@4 -o results/${sample}.bam
    fi

    # Index BAM (if not present)
    if [[ ! -f results/${sample}.bam.bai ]]; then
        samtools index -@4 results/${sample}.bam
    fi

    # Variant calling with lofreq
    lofreq call-parallel --pp-threads 4 -f data/ref/chrM.fa -o results/${sample}.vcf results/${sample}.bam

    # Compress VCF and index, then remove intermediate .vcf
    bgzip -c results/${sample}.vcf > results/${sample}.vcf.gz
    tabix -p vcf results/${sample}.vcf.gz
    rm results/${sample}.vcf
done

# Build collapsed.tsv (if not already present)
if [[ ! -f results/collapsed.tsv ]]; then
    {
        printf 'sample\tchrom\tpos\tref\talt\taf\n'
        for s in "${SAMPLES[@]}"; do
            bcftools query -f "${s}"$'\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' results/${s}.vcf.gz
        done
    } > results/collapsed.tsv
fi