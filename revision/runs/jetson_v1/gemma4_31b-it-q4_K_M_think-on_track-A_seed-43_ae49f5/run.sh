#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES="M117-bl M117-ch M117C1-bl M117C1-ch"
REF="data/ref/chrM.fa"

mkdir -p results

if [[ ! -f "${REF}.fai" ]]; then
    samtools faidx "$REF"
fi

if [[ ! -f "${REF}.bwt" ]]; then
    bwa index "$REF"
fi

for sample in $SAMPLES; do
    # Alignment and Sorting
    if [[ ! -f "results/${sample}.bam" ]]; then
        bwa mem -t "$THREADS" -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" "$REF" "data/raw/${sample}_1.fq.gz" "data/raw/${sample}_2.fq.gz" | samtools sort -@ "$THREADS" -o "results/${sample}.bam"
    fi

    # Indexing BAM
    if [[ ! -f "results/${sample}.bam.bai" ]]; then
        samtools index -@ "$THREADS" "results/${sample}.bam"
    fi

    # Variant Calling, Compression and Indexing
    if [[ ! -f "results/${sample}.vcf.gz.tbi" ]]; then
        lofreq call-parallel --pp-threads "$THREADS" -f "$REF" -b "results/${sample}.bam" > "results/${sample}.vcf"
        bgzip -f "results/${sample}.vcf"
        tabix -p vcf "results/${sample}.vcf.gz"
    fi
done

# Collapsed Table Generation
REBUILD=false
if [[ ! -f "results/collapsed.tsv" ]]; then
    REBUILD=true
else
    for sample in $SAMPLES; do
        if [[ "results/${sample}.vcf.gz" -nt "results/collapsed.tsv" ]]; then
            REBUILD=true
            break
        fi
    done
fi

if [ "$REBUILD" = true ]; then
    printf "sample\tchrom\tpos\tref\talt\taf\n" > results/collapsed.tsv
    for sample in $SAMPLES; do
        bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "results/${sample}.vcf.gz" >> results/collapsed.tsv
    done
fi