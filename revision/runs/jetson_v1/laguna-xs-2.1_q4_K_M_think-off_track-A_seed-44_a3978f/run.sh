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
    vcf_tbi="${vcf_gz}.tbi"
    
    # Check if all outputs exist and are up-to-date
    if [ -f "$bam" ] && [ -f "${bam%.bam}.bam.bai" ] && [ -f "$vcf_gz" ] && [ -f "$vcf_tbi" ]; then
        continue
    fi
    
    # Alignment with bwa mem
    bwa mem -t $THREADS \
        -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
        data/ref/chrM.fa \
        "data/raw/${sample}_1.fq.gz" \
        "data/raw/${sample}_2.fq.gz" | \
    samtools sort -@ $THREADS -o "$bam"
    
    # BAM indexing
    samtools index -@ $THREADS "$bam"
    
    # Variant calling with lofreq call-parallel
    tmp_vcf="results/${sample}.vcf"
    lofqreq call-parallel \
        --pp-threads $THREADS \
        -f data/ref/chrM.fa \
        -o "$tmp_vcf" \
        "$bam"
    
    # VCF compression and indexing
    bgzip -c "$tmp_vcf" > "$vcf_gz"
    tabix -p vcf "$vcf_gz"
    rm -f "$tmp_vcf"
done

# Collapsed TSV generation
collapsed="results/collapsed.tsv"
if [ ! -f "$collapsed" ]; then
    echo -e "sample\tchrom\tpos\tref\talt\taf" > "$collapsed"
fi

need_collapse=0
for sample in $SAMPLES; do
    vcf_gz="results/${sample}.vcf.gz"
    if [ ! -f "$collapsed" ] || [ "$vcf_gz" -nt "$collapsed" ]; then
        need_collapse=1
        break
    fi
done

if [ $need_collapse -eq 1 ]; then
    for sample in $SAMPLES; do
        bcftools query -f '{sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "results/${sample}.vcf.gz"
    done > "${collapsed}.tmp"
    
    echo -e "sample\tchrom\tpos\tref\talt\taf" | cat - "${collapsed}.tmp" > "$collapsed"
    rm -f "${collapsed}.tmp"
fi

exit 0