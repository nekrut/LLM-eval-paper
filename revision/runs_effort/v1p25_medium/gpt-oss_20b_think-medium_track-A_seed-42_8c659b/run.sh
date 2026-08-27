#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)
RAW_DIR=data/raw
REF_DIR=data/ref
RESULTS_DIR=results

mkdir -p "$RESULTS_DIR"

# Reference indexing
if [ ! -f "$REF_DIR/chrM.fa.fai" ]; then
    samtools faidx "$REF_DIR/chrM.fa"
fi
if [ ! -f "$REF_DIR/chrM.fa.amb" ]; then
    bwa index "$REF_DIR/chrM.fa"
fi

# Per-sample processing
for sample in "${SAMPLES[@]}"; do
    bam="$RESULTS_DIR/${sample}.bam"
    bai="${bam}.bai"
    vcf="$RESULTS_DIR/${sample}.vcf"
    vcfz="${vcf}.gz"

    fq1="$RAW_DIR/${sample}_1.fq.gz"
    fq2="$RAW_DIR/${sample}_2.fq.gz"

    # Alignment and sorting
    if [ ! -f "$bam" ] || [ "$fq1" -nt "$bam" ] || [ "$fq2" -nt "$bam" ]; then
        bwa mem -t "$THREADS" -R "@RG\\tID:${sample}\\tSM:${sample}\\tLB:${sample}\\tPL:ILLUMINA" \
            "$REF_DIR/chrM.fa" "$fq1" "$fq2" | \
        samtools sort -@ "$THREADS" -o "$bam"
    fi

    # BAM index
    if [ ! -f "$bai" ] || [ "$bam" -nt "$bai" ]; then
        samtools index -@ "$THREADS" "$bam"
    fi

    # Variant calling and compression
    if [ ! -f "$vcfz" ] || [ "$bam" -nt "$vcfz" ]; then
        lofreq call-parallel --pp-threads "$THREADS" -f "$REF_DIR/chrM.fa" -o "$vcf" "$bam"
        bcftools view -O z -o "$vcfz" "$vcf"
        tabix -p vcf "$vcfz"
        rm -f "$vcf"
    fi
done

# Collapse step
collapsed="$RESULTS_DIR/collapsed.tsv"

rebuild=false
if [ ! -f "$collapsed" ]; then
    rebuild=true
else
    for sample in "${SAMPLES[@]}"; do
        vcfz="${RESULTS_DIR}/${sample}.vcf.gz"
        if [ "$vcfz" -nt "$collapsed" ]; then
            rebuild=true
            break
        fi
    done
fi

if $rebuild; then
    printf "sample\tchrom\tpos\tref\talt\taf\n" > "$collapsed"
    for sample in "${SAMPLES[@]}"; do
        vcfz="${RESULTS_DIR}/${sample}.vcf.gz"
        bcftools query -f "${sample}\\t%CHROM\\t%POS\\t%REF\\t%ALT\\t%INFO/AF" "$vcfz" >> "$collapsed"
    done
fi

exit 0