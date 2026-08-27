#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
REF="data/ref/chrM.fa"
OUT_DIR="results"

mkdir -p "$OUT_DIR"

if [[ ! -f "${REF}.fai" ]]; then
    samtools faidx "$REF"
fi

if [[ ! -f "${REF}.bwt" ]]; then
    bwa index "$REF"
fi

for SAMPLE in "${SAMPLES[@]}"; do
    BAM="$OUT_DIR/${SAMPLE}.bam"
    BAI="$OUT_DIR/${SAMPLE}.bam.bai"
    VCF_GZ="$OUT_DIR/${SAMPLE}.vcf.gz"
    VCF_TBI="$OUT_DIR/${SAMPLE}.vcf.gz.tbi"
    R1="data/raw/${SAMPLE}_1.fq.gz"
    R2="data/raw/${SAMPLE}_2.fq.gz"

    if [[ ! -f "$VCF_TBI" ]]; then
        RG="@RG\tID:${SAMPLE}\tSM:${SAMPLE}\tLB:${SAMPLE}\tPL:ILLUMINA"
        
        if [[ ! -f "$BAM" ]]; then
            bwa mem -t "$THREADS" -R "$RG" "$REF" "$R1" "$R2" | \
            samtools sort -@ "$THREADS" -o "$BAM"
        fi

        if [[ ! -f "$BAI" ]]; then
            samtools index -@ "$THREADS" "$BAM"
        fi

        VCF_UNCOMPRESSED="$OUT_DIR/${SAMPLE}.vcf"
        lofreq call-parallel --pp-threads "$THREADS" -f "$REF" -o "$VCF_UNCOMPRESSED" "$BAM"
        
        bgzip -c "$VCF_UNCOMPRESSED" > "$VCF_GZ"
        tabix -p vcf "$VCF_GZ"
        rm "$VCF_UNCOMPRESSED"
    fi
done

COLLAPSED="$OUT_DIR/collapsed.tsv"
NEEDS_COLLAPSE=false
if [[ ! -f "$COLLAPSED" ]]; then
    NEEDS_COLLAPSE=true
else
    for SAMPLE in "${SAMPLES[@]}"; do
        VCF_GZ="$OUT_DIR/${SAMPLE}.vcf.gz"
        if [[ "$VCF_GZ" -nt "$COLLAPSED" ]]; then
            NEEDS_COLLAPSE=true
            break
        fi
    done
fi

if [ "$NEEDS_COLLAPSE" = true ]; then
    printf "sample\tchrom\tpos\tref\talt\taf\n" > "$COLLAPSED"
    for SAMPLE in "${SAMPLES[@]}"; do
        VCF_GZ="$OUT_DIR/${SAMPLE}.vcf.gz"
        bcftools query -f "${SAMPLE}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "$VCF_GZ" >> "$COLLAPSED"
    done
fi

exit 0