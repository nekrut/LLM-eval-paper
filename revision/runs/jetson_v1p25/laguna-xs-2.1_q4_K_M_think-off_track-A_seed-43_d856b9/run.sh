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
    if [ ! -f "$bam" ] || [ ! -f "${bam}.bai" ]; then
        need_run=1
    elif [ ! -f "$vcf_gz" ] || [ ! -f "${vcf_gz}.tbi" ]; then
        need_run=1
    else
        # Check if any input is newer than outputs
        fq1="data/raw/${sample}_1.fq.gz"
        fq2="data/raw/${sample}_2.fq.gz"
        newest_input=$(ls -t "$fq1" "$fq2" data/ref/chrM.fa 2>/dev/null | head -1)
        if [ "$(stat -c %Y "$bam")" -lt "$(stat -c %Y "$newest_input")" ]; then
            need_run=1
        fi
    fi
    
    if [ $need_run -eq 0 ]; then
        continue
    fi
    
    # Alignment and BAM processing
    bwa mem -t $THREADS -R "@RG	ID:${sample}	SM:${sample}	LB:${sample}	PL:ILLUMINA" \
        data/ref/chrM.fa \
        "data/raw/${sample}_1.fq.gz" \
        "data/raw/${sample}_2.fq.gz" | \
    samtools sort -@ $THREADS -o "$bam"
    
    samtools index -@ $THREADS "$bam"
    
    # Variant calling with lofreq
    lofreq call-parallel --pp-threads $THREADS -f data/ref/chrM.fa -o "$vcf_uncompressed" "$bam"
    
    # Compress and index VCF
    bgzip -c "$vcf_uncompressed" > "$vcf_gz"
    tabix -p vcf "$vcf_gz"
    rm -f "$vcf_uncompressed"
done

# Collapsed TSV (idempotent)
collapsed="results/collapsed.tsv"
need_collapse=0

if [ ! -f "$collapsed" ]; then
    need_collapse=1
else
    for sample in $SAMPLES; do
        vcf_gz="results/${sample}.vcf.gz"
        if [ "$(stat -c %Y "$collapsed")" -lt "$(stat -c %Y "$vcf_gz")" ]; then
            need_collapse=1
            break
        fi
    done
fi

if [ $need_collapse -eq 0 ]; then
    exit 0
fi

# Generate collapsed.tsv with header
echo -e "sample\tchrom\tpos\tref\talt\taf" > "$collapsed"

for sample in $SAMPLES; do
    bcftools query -f '{sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' \
        "results/${sample}.vcf.gz" >> "$collapsed"
done