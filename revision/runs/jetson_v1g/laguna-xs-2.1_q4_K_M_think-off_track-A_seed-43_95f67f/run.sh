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
    vcf_gz="results/${sample}.vcf.gz"
    
    # Alignment and sorting (idempotent check)
    if [ ! -f "$bam" ] || [ "data/raw/${sample}_1.fq.gz" -nt "$bam" ]; then
        bwa mem -t $THREADS -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
            data/ref/chrM.fa \
            <(zcat "data/raw/${sample}_1.fq.gz") \
            <(zcat "data/raw/${sample}_2.fq.gz") | \
        samtools sort -@ $THREADS -o "$bam"
    fi
    
    # BAM indexing (idempotent check)
    if [ ! -f "${bam}.bai" ] || [ "$bam" -nt "${bam}.bai" ]; then
        samtools index -@ $THREADS "$bam"
    fi
    
    # Variant calling with lofreq (idempotent check)
    vcf_uncompressed="results/${sample}.vcf"
    if [ ! -f "$vcf_gz" ] || [ "$bam" -nt "$vcf_gz" ]; then
        lofreq call-parallel --pp-threads $THREADS --verbose \
            --ref data/ref/chrM.fa --out "$vcf_uncompressed" --sig --bonf "$bam"
        
        bgzip -c "$vcf_uncompressed" > "$vcf_gz"
        tabix -p vcf "$vcf_gz"
        rm -f "$vcf_uncompressed"
    fi
done

# Collapsed TSV (idempotent check)
collapsed="results/collapsed.tsv"
need_collapse=false

if [ ! -f "$collapsed" ]; then
    need_collapse=true
else
    for sample in $SAMPLES; do
        if [ "results/${sample}.vcf.gz" -nt "$collapsed" ]; then
            need_collapse=true
            break
        fi
    done
fi

if [ "$need_collapse" = true ]; then
    echo -e "sample\tchrom\tpos\tref\talt\taf" > "$collapsed"
    for sample in $SAMPLES; do
        bcftools query -f '{sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' \
            "results/${sample}.vcf.gz" >> "$collapsed"
    done
fi