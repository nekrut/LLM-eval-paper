#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES="M117-bl M117-ch M117C1-bl M117C1-ch"
RESULTS_DIR="results"

mkdir -p "$RESULTS_DIR"

# Reference indexing (idempotent)
if [ ! -f "data/ref/chrM.fa.ind" ] || [ "data/ref/chrM.af" -nt "data/ref/chrM.fa.ind" ]; then
    samtools faidx data/ref/chrM.fa > /dev/null 2>&1
    bwa index data/ref/chrM.fa > /dev/null 2>&1
fi

# Per-sample processing
for sample in $SAMPLES; do
    # Alignment
    if [ ! -f "results/${sample}.bam" ] || [ "data/raw/${sample}_1.fq.gz" -nt "results/${sample}.bam" ] || [ "data/raw/${sample}_2.fq.gz" -nt "results/${sample}.bam" ]; then
        bwa mem -t $THREADS data/ref/chrM.fa data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz 2>/dev/null | samtools sort -@ $THREADS -o results/${sample}.bam > /dev/null
    fi

    # Index BAM
    if [ ! -f "results/${sample}.bam.bai" ] || [ "results/${sample}.bam" -nt "results/${sample}.bam.bai" ]; then
        samtools index -@ $THREADS results/${sample}.bam > /dev/null
    fi

    # Variant calling with lofreq call-parallel (idempotent)
    if [ ! -f "results/${sample}.vcf.gz" ] || [ "results/${sample}.bam.bai" -nt "results/${sample}.vcf.gz" ]; then
        lofreq call-parallel --pp-threads $THREADS --verbose \
            --ref data/ref/chrM.fa --out results/${sample}.vcf \
            --sig \
            --bonf \
            results/${sample}.bam > /dev/null 2>&1

        # Compression and indexing
        bgzip -c results/${sample}.vcf > results/${sample}.vcf.gz > /dev/null
        tabix -p vcf results/${sample}.vcf.gz > results/${sample}.vcf.gz.tbi > /dev/null
        rm -f results/${sample}.vcf
    fi

done

# Collapse step (idempotent)
if [ ! -f "results/collapsed.tsv" ] || [ "results/*.vcf.gz" -nt "results/collapsed.tsv" ]; then
    echo -e "sample\tchrom\tpos\tref\talt\taf" > results/collapsed.tsv
    for sample in $SAMPLES; do
        bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" results/${sample}.vcf.gz >> results/collapsed.tsv
    done
fi

exit 0