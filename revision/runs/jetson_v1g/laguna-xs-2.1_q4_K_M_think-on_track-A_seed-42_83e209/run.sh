#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES="M117-bl M117-ch M117C1-bl M117C1-ch"

mkdir -p results

# Reference indexing (idempotent)
if [[ ! -f data/ref/chrM.fa.fai ]]; then
    samtools faidx data/ref/chrM.fa
fi

for idx_ext in amb ann bwt pac sa; do
    if [[ ! -f "data/ref/chrM.fa.$idx_ext" ]]; then
        bwa index data/ref/chrM.fa
        break
    fi
done

# Per-sample processing
for sample in $SAMPLES; do
    bam="results/${sample}.bam"
    vcf_gz="results/${sample}.vcf.gz"
    
    # Alignment and sorting (idempotent)
    if [[ ! -f "$bam" ]]; then
        bwa mem -t $THREADS -R "@RG	ID:${sample}	SM:${sample}	LB:${sample}	PL:ILLUMINA" \
            data/ref/chrM.fa \
            "data/raw/${sample}_1.fq.gz" \
            "data/raw/${sample}_2.fq.gz" | \
        samtools sort -@ $THREADS -o "$bam"
    fi
    
    # BAM indexing (idempotent)
    if [[ ! -f "${bam}.bai" ]]; then
        samtools index -@ $THREADS "$bam"
    fi
    
    # Variant calling with lofreq (idempotent)
    vcf_uncompressed="results/${sample}.vcf"
    if [[ ! -f "$vcf_gz" ]] || [[ "$(find data/ref/chrM.fa data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz "$bam" -type f -print0 2>/dev/null | tr '\0' '\n' | sort -rz | head -1)" -nt "$vcf_gz" ]]; then
        lofreq call-parallel --pp-threads $THREADS --verbose \
            --ref data/ref/chrM.fa --out "$vcf_uncompressed" --sig --bonf \
            "$bam"
    fi
    
    # VCF compression and indexing (idempotent)
    if [[ ! -f "$vcf_gz" ]] || [[ "$(find "$vcf_uncompressed" -type f 2>/dev/null | head -1)" -nt "$vcf_gz" ]]; then
        bgzip -c "$vcf_uncompressed" > "$vcf_gz"
    fi
    
    if [[ ! -f "${vcf_gz}.tbi" ]] || [[ "$(find "$vcf_gz" -type f 2>/dev/null | head -1)" -nt "${vcf_gz}.tbi" ]]; then
        tabix -p vcf "$vcf_gz"
    fi
    
    rm -f "$vcf_uncompressed"
done

# Create collapsed.tsv (idempotent)
collapsed="results/collapsed.tsv"
need_collapse=false

if [[ ! -f "$collapsed" ]]; then
    need_collapse=true
else
    for sample in $SAMPLES; do
        vcf_gz="results/${sample}.vcf.gz"
        if [[ -f "$vcf_gz" ]] && [[ "$(find data/ref/chrM.fa "data/raw/${sample}_1.fq.gz" "data/raw/${sample}_2.fq.gz" results/${sample}.bam "$vcf_gz" -type f 2>/dev/null | tr '\n' ' ')" -nt "$collapsed" ]]; then
            need_collapse=true
            break
        fi
    done
fi

if $need_collapse; then
    echo -e "sample\tchrom\tpos\tref\talt\taf" > "$collapsed"
    for sample in $SAMPLES; do
        bcftools query -f '{sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' \
            "results/${sample}.vcf.gz" >> "$collapsed"
    done
fi

exit 0