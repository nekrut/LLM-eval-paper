#!/usr/bin/env bash
set -euo pipefail

THREADS=4
samples=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

mkdir -p results

ref="data/ref/chrM.fa"
if [ ! -f "${ref}.fai" ]; then
    samtools faidx "$ref"
fi
if [ ! -f "${ref}.amb" ]; then
    bwa index "$ref"
fi

for sample in "${samples[@]}"; do
    fq1="data/raw/${sample}_1.fq.gz"
    fq2="data/raw/${sample}_2.fq.gz"
    bam="results/${sample}.bam"
    bai="results/${sample}.bam.bai"
    vcf="results/${sample}.vcf"
    vcfz="${vcf}.gz"
    tbi="${vcfz}.tbi"

    if [ ! -f "$bam" ] || [ "$fq1" -nt "$bam" ] || [ "$fq2" -nt "$bam" ]; then
        bwa mem -t "$THREADS" -R "@RG\\tID:${sample}\\tSM:${sample}\\tLB:${sample}\\tPL:ILLUMINA" \
            "$ref" "$fq1" "$fq2" | samtools sort -@ "$THREADS" -o "$bam"
    fi

    if [ ! -f "$bai" ] || [ "$bam" -nt "$bai" ]; then
        samtools index -@ "$THREADS" "$bam"
    fi

    need_call=false
    if [ ! -f "$vcfz" ] || [ "$bam" -nt "$vcfz" ]; then
        need_call=true
    fi
    if $need_call; then
        lofreq call-parallel --pp-threads "$THREADS" --verbose \
            --ref "$ref" --out "$vcf" \
            --sig --bonf \
            "$bam"
        bgzip -c "$vcf" > "$vcfz"
        rm -f "$vcf"
    fi

    if [ ! -f "$tbi" ] || [ "$vcfz" -nt "$tbi" ]; then
        tabix -p vcf "$vcfz"
    fi
done

collapsed="results/collapsed.tsv"
need_collapse=false
if [ ! -f "$collapsed" ]; then
    need_collapse=true
else
    for sample in "${samples[@]}"; do
        if [ "results/${sample}.vcf.gz" -nt "$collapsed" ]; then
            need_collapse=true
            break
        fi
    done
fi

if $need_collapse; then
    tmp=$(mktemp)
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$tmp"
    for sample in "${samples[@]}"; do
        bcftools query -f '{sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "results/${sample}.vcf.gz" >> "$tmp"
    done
    mv "$tmp" "$collapsed"
fi