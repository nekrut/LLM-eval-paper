#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES="M117-bl M117-ch M117C1-bl M117C1-ch"
mkdir -p results

# Reference indexing (once)
if [[ ! -f data/ref/chrM.fa.fai ]]; then
    samtools faidx data/ref/chrM.fa
fi
if [[ ! -f data/ref/chrM.fa.bwt ]]; then
    bwa index data/ref/chrM.fa
fi

for sample in $SAMPLES; do
    # Alignment
    if [[ ! -f results/${sample}.bam ]]; then
        bwa mem -t $THREADS -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" data/ref/chrM.fa data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz | samtools sort -@ $THREADS -o results/${sample}.bam
    fi

    # BAM indexing
    if [[ ! -f results/${sample}.bam.bai ]]; then
        samtools index -@ $THREADS results/${sample}.bam
    fi

    # Variant calling
    if [[ ! -f results/${sample}.vcf ]]; then
        lofreq call-parallel --pp-threads $THREADS -f data/ref/chrM.fa -o results/${sample}.vcf results/${sample}.bam
    fi

    # VCF compression and indexing
    if [[ ! -f results/${sample}.vcf.gz ]]; then
        bgzip -c results/${sample}.vcf > results/${sample}.vcf.gz
        tabix -p vcf results/${sample}.vcf.gz
        rm results/${sample}.vcf
    fi
done

# Collapse step
if [[ ! -f results/collapsed.tsv ]]; then
    need_rebuild=1
else
    need_rebuild=0
    for sample in $SAMPLES; do
        if [ results/${sample}.vcf.gz -nt results/collapsed.tsv ]; then
            need_rebuild=1
            break
        fi
    done
fi

if [[ $need_rebuild -eq 1 ]]; then
    TMP_COLLAPSED=$(mktemp)
    echo "sample\tchrom\tpos\tref\talt\taf" > "$TMP_COLLAPSED"
    for sample in $SAMPLES; do
        bcftools query -f '{sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' results/${sample}.vcf.gz >> "$TMP_COLLAPSED"
    done
    mv "$TMP_COLLAPSED" results/collapsed.tsv
fi