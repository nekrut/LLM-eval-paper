#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES="M117-bl M117-ch M117C1-bl M117C1-ch"

mkdir -p results

# Reference indexing (once)
if [[ ! -f data/ref/chrM.fa.fai ]]; then
    samtools faidx data/ref/chrM.fa
fi

for ext in amb ann bwt pac sa; do
    if [[ ! -f "data/ref/chrM.fa.$ext" ]]; then
        bwa index data/ref/chrM.fa
        break
    fi
done

# Per-sample processing
for sample in $SAMPLES; do
    bam="results/${sample}.bam"
    vcf_gz="results/${sample}.vcf.gz"
    
    # Alignment and sorting (idempotent check)
    if [[ ! -f "$bam" ]] || [[ "data/raw/${sample}_1.fq.gz" -nt "$bam" ]]; then
        bwa mem -t $THREADS -R "@RG	ID:${sample}	SM:${sample}	LB:${sample}	PL:ILLUMINA" \
            data/ref/chrM.fa \
            <(zcat "data/raw/${sample}_1.fq.gz") \
            <(zcat "data/raw/${sample}_2.fq.gz") | \
        samtools sort -@ $THREADS -o "$bam"
    fi
    
    # BAM indexing (idempotent check)
    if [[ ! -f "${bam}.bai" ]] || [[ "$bam" -nt "${bam}.bai" ]]; then
        samtools index -@ $THREADS "$bam"
    fi
    
    # Variant calling with lofreq (idempotent check)
    vcf="${vcf_gz%.gz}"
    if [[ ! -f "$vcf" ]] || [[ "$bam" -nt "$vcf" ]]; then
        lofreq call-parallel --pp-threads $THREADS --ref data/ref/chrM.fa \
            --out "$vcf" "$bam"
    fi
    
    # VCF compression and indexing (idempotent check)
    if [[ ! -f "$vcf_gz" ]] || [[ "$vcf" -nt "$vcf_gz" ]]; then
        bgzip -c "$vcf" > "$vcf_gz"
        tabix -p vcf "$vcf_gz"
        rm -f "$vcf"
    fi
done

# Collapsed TSV (idempotent check)
collapsed="results/collapsed.tsv"
need_rebuild=0

if [[ ! -f "$collapsed" ]]; then
    need_rebuild=1
else
    for sample in $SAMPLES; do
        vcf_gz="results/${sample}.vcf.gz"
        if [[ "$vcf_gz" -nt "$collapsed" ]]; then
            need_rebuild=1
            break
        fi
    done
fi

if [[ $need_rebuild -eq 1 ]]; then
    {
        printf 'sample\tchrom\tpos\tref\talt\taf\n'
        for sample in $SAMPLES; do
            bcftools query -f '{sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' \
                "results/${sample}.vcf.gz"
        done
    } > "$collapsed"
fi