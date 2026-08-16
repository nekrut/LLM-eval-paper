#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
REF="data/ref/chrM.fa"
OUTDIR="results"

mkdir -p "$OUTDIR"

if [[ ! -f "${REF}.fai" ]]; then
    samtools faidx "$REF"
fi

if [[ ! -f "${REF}.bwt" ]]; then
    bwa index "$REF"
fi

for sample in "${SAMPLES[@]}"; do
    BAM="${OUTDIR}/${sample}.bam"
    BAI="${BAM}.bai"
    VCF_GZ="${OUTDIR}/${sample}.vcf.gz"
    VCF_TBI="${VCF_GZ}.tbi"

    if [[ ! -f "$BAM" ]]; then
        bwa mem -t "$THREADS" -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
            "$REF" "data/raw/${sample}_1.fq.gz" "data/raw/${sample}_2.fq.gz" | \
            samtools sort -@ "$THREADS" -o "$BAM"
    fi

    if [[ ! -f "$BAI" ]]; then
        samtools index -@ "$THREADS" "$BAM"
    fi

    if [[ ! -f "$VCF_TBI" ]]; then
        lofreq call-parallel --pp-threads "$THREADS" -f "$REF" -b "$BAM" > "${OUTDIR}/${sample}.vcf"
        bgzip -c "${OUTDIR}/${sample}.vcf" > "$VCF_GZ"
        tabix -p vcf "$VCF_GZ"
        rm "${OUTDIR}/${sample}.vcf"
    fi
done

COLLAPSED="${OUTDIR}/collapsed.tsv"
NEEDS_REBUILD=false
if [[ ! -f "$COLLAPSED" ]]; then
    NEEDS_REBUILD=true
else
    for sample in "${SAMPLES[@]}"; do
        if [[ "${OUTDIR}/${sample}.vcf.gz" -nt "$COLLAPSED" ]]; then
            NEEDS_REBUILD=true
            break
        fi
    done
fi

if [ "$NEEDS_REBUILD" = true ]; then
    printf "sample\tchrom\tpos\tref\talt\taf\n" > "$COLLAPSED"
    for sample in "${SAMPLES[@]}"; do
        bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "${OUTDIR}/${sample}.vcf.gz" >> "$COLLAPSED"
    done
fi