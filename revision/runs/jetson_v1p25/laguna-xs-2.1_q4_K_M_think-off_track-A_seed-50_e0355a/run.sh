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
    
    # Alignment and BAM creation (idempotent check)
    if [ ! -f "$bam" ] || [ "data/raw/${sample}_1.fq.gz" -nt "$bam" ]; then
        bwa mem -t $THREADS -R "@RG	ID:${sample}	SM:${sample}	LB:${sample}	PL:ILLUMINA" \
            data/ref/chrM.fa \
            "data/raw/${sample}_1.fq.gz" \
            "data/raw/${sample}_2.fq.gz" | \
        samtools sort -@ $THREADS -o "$bam"
    fi
    
    # BAM indexing (idempotent check)
    if [ ! -f "${bam}.bai" ] || [ "$bam" -nt "${bam}.bai" ]; then
        samtools index -@ $THREADS "$bam"
    fi
    
    # Variant calling with lofreq (idempotent check)
    if [ ! -f "$vcf_gz" ] || [ "$bam" -nt "$vcf_uncompressed" ]; then
        lofreq call-parallel --pp-threads $THREADS -f data/ref/chrM.fa -o "$vcf_uncompressed" "$bam"
        
        bgzip -c "$vcf_uncompressed" > "$vcf_gz"
        tabix -p vcf "$vcf_gz"
        rm -f "$vcf_uncompressed"
    fi
done

# Collapsed TSV generation (idempotent check)
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

exit 0