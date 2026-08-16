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
    bai="${bam}.bai"
    vcf_gz="${bam%.bam}.vcf.gz"
    vcf_tbi="${vcf_gz}.tbi"
    
    # Check if all outputs exist and are up-to-date
    need_run=0
    if [ ! -f "$bam" ] || [ ! -f "$bai" ] || [ ! -f "$vcf_gz" ] || [ ! -f "$vcf_tbi" ]; then
        need_run=1
    else
        # Check timestamps against inputs
        fq1="data/raw/${sample}_1.fq.gz"
        fq2="data/raw/${sample}_2.fq.gz"
        if [ "$fq1" -nt "$bam" ] || [ "$fq2" -nt "$bam" ]; then
            need_run=1
        fi
    fi
    
    if [ $need_run -eq 0 ]; then
        continue
    fi
    
    # Alignment with bwa mem, pipe to samtools sort
    bwa mem -t $THREADS -R "@RG	ID:${sample}	SM:${sample}	LB:${sample}	PL:ILLUMINA" \
        data/ref/chrM.fa \
        "data/raw/${sample}_1.fq.gz" \
        "data/raw/${sample}_2.fq.gz" | \
    samtools sort -@ $THREADS -o "$bam" -
    
    # BAM indexing
    samtools index -@ $THREADS "$bam"
    
    # Variant calling with lofreq
    lofreq call-parallel --pp-threads $THREADS -f data/ref/chrM.fa -o "${bam%.bam}.vcf" "$bam"
    
    # VCF compression and indexing
    bgzip -c "${bam%.bam}.vcf" > "$vcf_gz"
    tabix -p vcf "$vcf_gz"
    rm -f "${bam%.bam}.vcf"
done

# Collapsed TSV generation
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

if [ $need_collapse -eq 0 ]; then
    exit 0
fi

# Generate collapsed TSV with header
echo -e "sample\tchrom\tpos\tref\talt\taf" > "$collapsed"

for sample in $SAMPLES; do
    bcftools query -f '{sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' \
        "results/${sample}.vcf.gz" >> "$collapsed"
done