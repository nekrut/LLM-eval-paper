#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES="M117-bl M117-ch M117C1-bl M117C1-ch"

mkdir -p results

# Reference indexing (idempotent)
if [ ! -f data/ref/chrM.fa.fai ]; then
    samtools faidx data/ref/chrM.fa
fi

for ext in amb ann bwt pac sa; do
    if [ ! -f "data/ref/chrM.fa.$ext" ]; then
        bwa index data/ref/chrM.fa
        break
    fi
done

# Per-sample processing (idempotent)
for sample in $SAMPLES; do
    bam="results/${sample}.bam"
    vcf_uncompressed="results/${sample}.vcf"
    vcf_gz="results/${sample}.vcf.gz"
    
    # Check if all outputs exist and are up-to-date
    need_run=0
    if [ ! -f "$bam" ] || [ data/raw/${sample}_1.fq.gz -nt "$bam" ]; then
        need_run=1
    fi
    if [ $need_run -eq 0 ] && [ ! -f "${bam}.bai" ]; then
        need_run=1
    fi
    if [ $need_run -eq 0 ] && ([ ! -f "$vcf_gz" ] || [ "$bam" -nt "$vcf_gz" ]); then
        need_run=1
    fi
    
    if [ $need_run -eq 1 ]; then
        # Alignment with bwa mem (read group with literal \t)
        bwa mem -t $THREADS -R "@RG	ID:${sample}	SM:${sample}	LB:${sample}	PL:ILLUMINA" data/ref/chrM.fa data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz | \
            samtools sort -@ $THREADS -o "$bam"
        
        # BAM indexing
        samtools index -@ $THREADS "$bam"
        
        # Variant calling with lofreq
        lofreq call-parallel --pp-threads $THREADS -f data/ref/chrM.fa -o "$vcf_uncompressed" "$bam"
        
        # VCF compression and indexing
        bgzip -c "$vcf_uncompressed" > "$vcf_gz"
        tabix -p vcf "$vcf_gz"
        rm -f "$vcf_uncompressed"
    fi
done

# Collapsed TSV (idempotent)
collapsed="results/collapsed.tsv"
need_collapse=0

if [ ! -f "$collapsed" ]; then
    need_collapse=1
else
    for sample in $SAMPLES; do
        if [ "results/${sample}.vcf.gz" -nt "$collapsed" ]; then
            need_collapse=1
            break
        fi
    done
fi

if [ $need_collapse -eq 1 ]; then
    echo -e "sample\tchrom\tpos\tref\talt\taf" > "$collapsed"
    for sample in $SAMPLES; do
        bcftools query -f '{sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "results/${sample}.vcf.gz" >> "$collapsed"
    done
fi