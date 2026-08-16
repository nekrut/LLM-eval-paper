#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)
REF="data/ref/chrM.fa"
OUTDIR="results"

mkdir -p "$OUTDIR"

# Reference indexing (idempotent)
if [[ ! -f "${REF}.fai" ]] || [[ ! -f "${REF}.bwt" ]]; then
    samtools faidx "$REF"
    bwa index "$REF"
fi

for sample in "${SAMPLES[@]}"; do
    VCF_TBI="${OUTDIR}/${sample}.vcf.gz.tbi"
    if [[ -f "$VCF_TBI" ]]; then
        continue
    fi

    BAM="${OUTDIR}/${sample}.bam"
    BAI="${OUTDIR}/${sample}.bam.bai"
    VCF="${OUTDIR}/${sample}.vcf"
    VCF_GZ="${OUTDIR}/${sample}.vcf.gz"

    # Alignment & Sorting
    if [[ ! -f "$BAM" ]]; then
        bwa mem -t "$THREADS" -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" "$REF" "data/raw/${sample}_1.fq.gz" "data/raw/${sample}_2.fq.gz" | samtools sort -@ "$THREADS" -o "$BAM"
    fi

    # BAM Indexing
    if [[ ! -f "$BAI" ]]; then
        samtools index -@ "$THREADS" "$BAM"
    fi

    # Variant Calling & Compression
    if [[ ! -f "$VCF_GZ" ]]; then
        lofreq call-parallel --pp-threads "$THREADS" -f "$REF" -o "$VCF" "$BAM"
        bgzip -c "$VCF" > "$VCF_GZ"
        tabix -p vcf "$VCF_GZ"
        rm -f "$VCF"
    fi
done

# Collapsed TSV (idempotent)
COLLAPSED="${OUTDIR}/collapsed.tsv"
needs_rebuild=false
if [[ ! -f "$COLLAPSED" ]]; then
    needs_rebuild=true
else
    for sample in "${SAMPLES[@]}"; do
        if [[ "${OUTDIR}/${sample}.vcf.gz" -nt "$COLLAPSED" ]]; then
            needs_rebuild=true
            break
        fi
    done
fi

if $needs_rebuild; then
    {
        printf "sample\tchrom\tpos\tref\talt\taf\n"
        for sample in "${SAMPLES[@]}"; do
            bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "${OUTDIR}/${sample}.vcf.gz"
        done
    } > "$COLLAPSED"
fi