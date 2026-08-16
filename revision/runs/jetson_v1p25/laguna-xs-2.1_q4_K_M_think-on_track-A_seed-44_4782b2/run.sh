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
    vcf_uncomp="results/${sample}.vcf"
    vcf_gz="results/${sample}.vcf.gz"
    vcf_tbi="results/${sample}.vcf.gz.tbi"
    
    # Check if all outputs exist and are up-to-date
    if [ -f "$bam" ] && [ -f "${bam%.bam}.bam.bai" ] && [ -f "$vcf_gz" ] && [ -f "$vcf_tbi" ]; then
        continue
    fi
    
    # Alignment with bwa mem (idempotent)
    if [ ! -f "$bam" ]; then
        bwa mem -t $THREADS -R "@RG	ID:${sample}	SM:${sample}	LB:${sample}	PL:ILLUMINA" \
            data/ref/chrM.fa \
            "data/raw/${sample}_1.fq.gz" \
            "data/raw/${sample}_2.fq.gz" | \
        samtools sort -@ $THREADS -o "$bam"
    fi
    
    # BAM indexing (idempotent)
    if [ ! -f "${bam}.bai" ]; then
        samtools index -@ $THREADS "$bam"
    fi
    
    # Variant calling with lofreq (idempotent)
    if [ ! -f "$vcf_uncomp" ] || [ "$bam" -nt "$vcf_uncomp" ]; then
        lofreq call-parallel --pp-threads $THREADS -f data/ref/chrM.fa -o "$vcf_uncomp" "$bam"
    fi
    
    # VCF compression and indexing (idempotent)
    if [ ! -f "$vcf_gz" ] || [ "$vcf_uncomp" -nt "$vcf_gz" ]; then
        bgzip -c "$vcf_uncomp" > "$vcf_gz"
        tabix -p vcf "$vcf_gz"
        rm -f "$vcf_uncomp"
    fi
done

# Collapsed TSV (idempotent)
collapsed="results/collapsed.tsv"
need_collapse=false

if [ ! -f "$collapsed" ]; then
    need_collapse=true
else
    for sample in $SAMPLES; do
        vcf_gz="results/${sample}.vcf.gz"
        if [ "$vcf_gz" -nt "$collapsed" ]; then
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