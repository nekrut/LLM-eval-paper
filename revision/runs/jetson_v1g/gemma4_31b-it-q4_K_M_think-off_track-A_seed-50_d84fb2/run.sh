#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
REF="data/ref/chrM.fa"
OUTDIR="results"

mkdir -p "$OUTDIR"

# Reference Indexing
if [[ ! -f "${REF}.fai" ]]; then
    samtools faidx "$REF"
fi

if [[ ! -f "${REF}.bwt" ]]; then
    bwa index "$REF"
fi

for SAMPLE in "${SAMPLES[@]}"; do
    BAM="$OUTDIR/${SAMPLE}.bam"
    BAI="$BAM.bai"
    VCF_GZ="$OUTDIR/${SAMPLE}.vcf.gz"
    TBI="$VCF_GZ.tbi"
    
    # Alignment and Sorting
    if [[ ! -f "$BAM" ]]; then
        bwa mem -t "$THREADS" \
            -R "@RG\tID:${SAMPLE}\tSM:${SAMPLE}\tLB:${SAMPLE}\tPL:ILLUMINA" \
            "$REF" "data/raw/${SAMPLE}_1.fq.gz" "data/raw/${SAMPLE}_2.fq.gz" | \
            samtools sort -@ "$THREADS" -o "$BAM"
    fi

    # BAM Indexing
    if [[ ! -f "$BAI" ]]; then
        samtools index -@ "$THREADS" "$BAM"
    fi

    # Variant Calling
    if [[ ! -f "$TBI" ]]; then
        VCF_RAW="$OUTDIR/${SAMPLE}.vcf"
        lofreq call-parallel --pp-threads "$THREADS" \
            --ref "$REF" \
            --out "$VCF_RAW" \
            "$BAM"
        
        bgzip -f "$VCF_RAW"
        tabix -p vcf "$VCF_GZ"
    fi
done

# Collapsed Table
COLLAPSED="$OUTDIR/collapsed.tsv"
NEEDS_UPDATE=0

if [[ ! -f "$COLLAPSED" ]]; then
    NEEDS_UPDATE=1
else
    for SAMPLE in "${SAMPLES[@]}"; do
        if [[ "$OUTDIR/${SAMPLE}.vcf.gz" -nt "$COLLAPSED" ]]; then
            NEEDS_UPDATE=1
            break
        fi
    done
fi

if [[ $NEEDS_UPDATE -eq 1 ]]; then
    printf "sample\tchrom\tpos\tref\talt\taf\n" > "$COLLAPSED"
    for SAMPLE in "${SAMPLES[@]}"; do
        bcftools query -f "${SAMPLE}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "$OUTDIR/${SAMPLE}.vcf.gz" >> "$COLLAPSED"
    done
fi