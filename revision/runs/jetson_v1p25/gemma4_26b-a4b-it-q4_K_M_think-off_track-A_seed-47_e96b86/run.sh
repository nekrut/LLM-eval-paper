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

for sample in "${SAMPLES[@]}"; do
    BAM="$OUT_DIR/${sample}.bam"
    BAI="$OUT_DIR/${sample}.bam.bai"
    VCF_GZ="$OUT_DIR/${sample}.vcf.gz"
    VCF_TBI="$OUT_DIR/${sample}.vcf.gz.tbi"
    R1="data/raw/${sample}_1.fq.gz"
    R2="data/raw/${sample}_2.fq.gz"

    if [[ ! -f "$VCF_TBI" ]]; then
        RG_STR="@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA"
        bwa mem -t "$THREADS" -R "$RG_STR" "$REF" "$R1" "$R2" | \
            samtools sort -@ "$THREADS" -o "$BAM"
        
        samtools index -@ "$THREADS" "$BAM"

        lofreq call-parallel --pp-threads "$THREADS" -f "$REF" -o "$OUT_DIR/${sample}.vcf" "$BAM"
        
        bgzip -c "$OUT_DIR/${sample}.vcf" > "$VCF_GZ"
        tabix -p vcf "$VCF_GZ"
        rm "$OUT_DIR/${sample}.vcf"
    fi
done

TSV="$OUT_DIR/collapsed.tsv"
NEEDS_COLLAPSE=false

if [[ ! -f "$TSV" ]]; then
    NEEDS_COLLAPSE=true
else
    for sample in "${SAMPLES[@]}"; do
        VCF_GZ="$OUT_DIR/${sample}.vcf.gz"
        if [[ "$VCF_GZ" -nt "$TSV" ]]; then
            NEEDS_COLLAPSE=true
            break
        fi
    done
fi

if [ "$NEEDS_COLLAPSE" = true ]; then
    printf "sample\tchrom\tpos\tref\talt\taf\n" > "$TSV"
    for sample in "${SAMPLES[@]}"; do
        VCF_GZ="$OUT_DIR/${sample}.vcf.gz"
        bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "$VCF_GZ" >> "$TSV"
    done
fi

exit 0