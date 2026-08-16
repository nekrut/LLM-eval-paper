#!/usr/bin/env bash
set -euo pipefail

THREADS=4
samples="M117-bl M117-ch M117C1-bl M117C1-ch"
results_dir="results"

mkdir -p "$results_dir"

# Reference indexing (once)
if [ ! -f "data/ref/chrM.fa.fai" ] || [ "data/ref/chrM.fa" -nt "data/ref/chrM.fa.fai" ]; then
    samtools faidx data/ref/chrM.fa
fi
if [ ! -f "data/ref/chrM.amb" ] || [ "data/ref/chrM.fa" -nt "data/ref/chrM.amb" ]; then
    bwa index data/ref/chrM.fa
fi

# Per-sample processing
for sample in $samples; do
    # Align
    if [ ! -f "results/${sample}.bam" ] || [ "data/raw/${sample}_1.2.fq.gz" -nt "results/${sample}.bam" ]; then
        bwa mem -t "$THREADS" -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
            data/raw/${sample}_1.2.fq.gz > results/${sample}.bam
    fi

    # Sort BAM
    if [ ! -f "results/${sample}.bam" ] || [ "data/raw/${sample}_1.2.fq.gz" -nt "results/${sample}.bam" ]; then
        samtools sort -@ "$THREADS" -o results/${sample}.bam
    fi

    # Index BAM
    if [ ! -f "results/${sample}.bai" ] || [ "data/raw/${sample}_1.2.fq.gz" -nt "results/${sample}.bam" ]; then
        samtools index -@ "$THREADS" results/${sample}.bam
    fi

    # Variant calling with lofreq call-parallel
    if [ ! -f "results/${sample}.vcf" ] || [ "data/raw/${sample}_1.2.fq.gz" -nt "results/${sample}.vcf" ]; then
        lofreq call-parallel --pp-threads 4 --verbose \
            --ref data/ref/chrM.fa --out results/${sample}.vcf \
            --sig --bonf results/${sample}.bam
    fi

    # Compress VCF with bgzip and index with tabix, remove intermediate .vcf
    if [ ! -f "results/${sample}.vcf.gz" ] || [ "data/raw/${sample}_1.2.fq.gz" -nt "results/${sample}.vcf.gz" ]; then
        bgzip -@ "$THREADS" results/${sample}.vcf > results/${sample}.vcf.gz
        tabix -p vcf results/${sample}.vcf.gz > results/${sample}.vcf.gz.tbi
        rm -f results/${sample}.vcf
    fi

done

# Collapse step
if [ ! -f "results/collapsed.tsv" ] || [ "$(find results -name '*.vcf.gz' | sort -r | head -n1)" -nt "results/collapsed.tsv" ]; then
    {
        echo "sample\tchrom\tpos\tref\talt\taf"
        for sample in $samples; do
            bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" results/${sample}.vcf.gz >> results/collapsed.tsv
        done
    } > results/collapsed.tsv.tmp && mv results/collapsed.tsv.tmp results/collapsed.tsv
fi

exit 0