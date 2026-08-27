#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES="M117-bl M117-ch M117C1-bl M117C1-ch"
RESULTS_DIR="results"

mkdir -p "$RESULTS_DIR"

# Reference indexing (once)
if [[ ! -f "data/ref/chrM.fa.ind" ]] || [[ data/ref/chrM.fa.ind -nt data/ref/chrM.fa ]]; then
    samtools faidx data/ref/chrM.fa
    bwa index data/ref/chrM.fa
fi

# Per-sample processing
for SAMPLE in $SAMPLES; do
    # Alignment
    if [[ ! -f "results/${SAMPLE}.bam" ]] || [[ results/${SAMPLE}.bam -nt data/raw/${SAMPLE}_1.fq.gz data/raw/${SAMPLE}_2.fq.gz ]]; then
        bwa mem -t $THREADS data/ref/chrM.fa data/raw/${SAMPLE}_1.fq.gz data/raw/${SAMPLE}_2.fq.gz 2>/dev/null | samtools sort -@ $THREADS -o results/${SAMPLE}.bam
    fi

    # Index BAM
    if [[ ! -f "results/${SAMPLE}.bam.bai" ]] || [[ results/${SAMPLE}.bam.bai -nt results/${SAMPLE}.bam ]]; then
        samtools index -@ $THREADS results/${SAMPLE}.bam
    fi

    # Variant calling with lofreq call-parallel
    if [[ ! -f "results/${SAMPLE}.vcf" ]] || [[ results/${SAMPLE}.vcf -nt results/${SAMPLE}.bam ]]; then
        lofreq call-parallel --pp-threads $THREADS --verbose \
            --ref data/ref/chrM.fa --out results/${SAMPLE}.vcf \
            --sig --bonf \
            results/${SAMPLE}.bam 2>/dev/null
    fi

    # Compress and index VCF
    if [[ ! -f "results/${SAMPLE}.vcf.gz" ]] || [[ results/${SAMPLE}.vcf.gz.ind -nt results/${SAMPLE}.vcf ]]; then
        bgzip -@ $THREADS results/${SAMPLE}.vcf
        tabix -p vcf -@ $THREADS results/${SAMPLE}.vcf.gz
        rm -f results/${SAMPLE}.vcf
    fi

done

# Collapse TSV
if [[ ! -f "results/collapsed.tsv" ]] || [[ results/collapsed.tsv -nt $(for S in $SAMPLES; do echo results/${S}.vcf.gz; done) ]]; then
    HEADER="sample\tchrom\tpos\tref\talt\taf"
    OUT=$(mktemp)
    for S in $SAMPLES; do
        bcftools query -f "${S}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" results/${S}.vcf.gz >> "$OUT"
    done
    echo "$HEADER" > "results/collapsed.tsv"
    cat "$OUT" >> "results/collapsed.tsv"
    rm -f "$OUT"
fi

exit 0