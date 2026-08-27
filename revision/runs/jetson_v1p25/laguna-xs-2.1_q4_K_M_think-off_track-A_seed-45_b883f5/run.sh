#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES="M117-bl M117-ch M117C1-bl M117C1-ch"

mkdir -p results

# Reference indexing (once)
if [ ! -f data/ref/chrM.fa.fai ]; then
    samtools faidx data/ref/chrM.fa
fi

for ext in amb ann bwt pac sa; do
    if [ ! -f "data/ref/chrM.fa.$ext" ]; then
        bwa index data/ref/chrM.fa
        break
    fi
done

# Per-sample processing
for sample in $SAMPLES; do
    bam="results/${sample}.bam"
    vcf_uncompressed="results/${sample}.vcf"
    vcf_gz="results/${sample}.vcf.gz"
    
    # Alignment and BAM creation (idempotent)
    if [ ! -f "$bam" ] || [ "data/raw/${sample}_1.fq.gz" -nt "$bam" ]; then
        bwa mem -t $THREADS -R "@RG	ID:${sample}	SM:${sample}	LB:${sample}	PL:ILLUMINA" \
            data/ref/chrM.fa \
            "data/raw/${sample}_1.fq.gz" \
            "data/raw/${sample}_2.fq.gz" | \
        samtools sort -@ $THREADS -o "$bam"
    fi
    
    # BAM indexing (idempotent)
    if [ ! -f "${bam}.bai" ] || [ "$bam" -nt "${bam}.bai" ]; then
        samtools index -@ $THREADS "$bam"
    fi
    
    # Variant calling with lofreq (idempotent)
    if [ ! -f "$vcf_gz" ] || [ "$bam" -nt "$vcf_gz" ]; then
        lofreq call-parallel --pp-threads $THREADS -f data/ref/chrM.fa -o "$vcf_uncompressed" "$bam"
        bgzip -c "$vcf_uncompressed" > "$vcf_gz"
        tabix -p vcf "$vcf_gz"
        rm -f "$vcf_uncompressed"
    fi
done

# Collapsed TSV generation (idempotent)
collapsed="results/collapsed.tsv"
need_collapse=0

if [ ! -f "$collapsed" ]; then
    need_collapse=1
else
    for sample in $SAMPLES; do
        vcf_gz="results/${sample}.vcf.gz"
        if [ "$vcf_gz" -nt "$collapsed" ]; then
            need_collapse=1
            break
        fi
    done
fi

if [ $need_collapse -eq 1 ]; then
    echo -e "sample\tchrom\tpos\tref\talt\taf" > "$collapsed"
    for sample in $SAMPLES; do
        bcftools query -f '{sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' \
            "results/${sample}.vcf.gz" >> "$collapsed"
    done
fi