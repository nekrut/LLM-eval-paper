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
    VCF_GZ="${OUT_DIR}/${sample}.vcf.gz"
    TBI="${VCF_GZ}.tbi"
    BAM="${OUT_DIR}/${sample}.bam"
    F1="data/raw/${sample}_1.fq.gz"
    F2="data/raw/${sample}_2.fq.gz"

    if [[ ! -f "$TBI" ]] || [[ "$F1" -nt "$TBI" ]] || [[ "$F2" -nt "$TBI" ]]; then
        bwa mem -t "$THREADS" -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" "$REF" "$F1" "$F2" | \
            samtools sort -@ "$THREADS" -o "$BAM"

        samtools index -@ "$THREADS" "$BAM"

        lofreq call-parallel --pp-threads "$THREADS" -f "$REF" "$BAM" > "${OUT_DIR}/${sample}.vcf"

        bgzip -c "${OUT_DIR}/${sample}.vcf" > "$VCF_GZ"
        rm "${OUT_DIR}/${sample}.vcf"
        tabix -p vcf "$VCF_GZ"
    fi
done

TSV="$OUT_DIR/collapsed.tsv"
REBUILD_TSV=false

if [[ ! -f "$TSV" ]]; then
    REBUILD_TSV=true
else
    for sample in "${SAMPLES[@]}"; do
        VCF_GZ="${OUT_DIR}/${sample}.vcf.gz"
        if [[ "$VCF_GZ" -nt "$TSV" ]]; then
            REBUILD_TSV=true
            break
        fi
    done
fi

if [ "$REBUILD_TSV" = true ]; then
    printf "sample\tchrom\tpos\tref\talt\taf\n" > "$TSV.tmp"
    for sample in "${SAMPLES[@]}"; do
        VCF_GZ="${OUT_DIR}/${sample}.vcf.gz"
        if [[ -f "$VCF_GZ" ]]; then
            bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "$VCF_GZ" >> "$TSV.tmp"
        fi
    done
    mv "$TSV.tmp" "$TSV"
fi