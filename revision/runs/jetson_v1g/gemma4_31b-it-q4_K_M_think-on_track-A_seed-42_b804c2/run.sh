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
    BAM="results/${sample}.bam"
    BAI="${BAM}.bai"
    VCF_GZ="results/${sample}.vcf.gz"
    TBI="${VCF_GZ}.tbi"

    if [[ ! -f "$BAM" ]]; then
        bwa mem -t "$THREADS" -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
            "$REF" "data/raw/${sample}_1.fq.gz" "data/raw/${sample}_2.fq.gz" | \
            samtools sort -@ "$THREADS" -o "$BAM"
    fi

    if [[ ! -f "$BAI" ]]; then
        samtools index -@ "$THREADS" "$BAM"
    fi

    if [[ ! -f "$TBI" ]]; then
        lofreq call-parallel --pp-threads "$THREADS" --verbose \
            --ref "$REF" --out "results/${sample}.vcf" \
            "$BAM"
        bgzip -f "results/${sample}.vcf"
        tabix -p vcf "$VCF_GZ"
    fi
done

COLLAPSED="results/collapsed.tsv"
REBUILD=false
if [[ ! -f "$COLLAPSED" ]]; then
    REBUILD=true
else
    for sample in $SAMPLES; do
        if [[ "results/${sample}.vcf.gz" -nt "$COLLAPSED" ]]; then
            REBUILD=true
            break
        fi
    done
fi

if [ "$REBUILD" = true ]; then
    printf "sample\tchrom\tpos\tref\talt\taf\n" > "$COLLAPSED"
    for sample in $SAMPLES; do
        bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "results/${sample}.vcf.gz" >> "$COLLAPSED"
    done
fi