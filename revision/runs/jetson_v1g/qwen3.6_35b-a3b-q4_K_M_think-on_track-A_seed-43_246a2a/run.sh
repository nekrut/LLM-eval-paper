#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)

mkdir -p results

# Reference indexing (once)
if [[ ! -f data/ref/chrM.fa.fai ]]; then
    samtools faidx data/ref/chrM.fa
fi
REF_IDX=(data/ref/chrM.fa.amb data/ref/chrM.fa.ann data/ref/chrM.fa.bwt data/ref/chrM.fa.pac data/ref/chrM.fa.sa)
if [[ ! -f "${REF_IDX[0]}" ]]; then
    bwa index data/ref/chrM.fa
fi

# Per-sample processing
for sample in "${SAMPLES[@]}"; do
    BAM="results/${sample}.bam"
    BAI="${BAM}.bai"
    VCF="results/${sample}.vcf"
    VCF_GZ="${VCF}.gz"
    VCF_TBI="${VCF_GZ}.tbi"

    # Idempotency: skip if all expected outputs exist
    [[ -f "$BAI" && -f "$VCF_TBI" ]] && continue

    # Alignment & sorting
    if [[ ! -f "$BAM" ]]; then
        bwa mem -t "$THREADS" \
            -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
            data/ref/chrM.fa \
            "data/raw/${sample}_1.fq.gz" \
            "data/raw/${sample}_2.fq.gz" | \
            samtools sort -@ "$THREADS" -o "$BAM" -
    fi

    # BAM indexing
    if [[ ! -f "$BAI" ]]; then
        samtools index -@ "$THREADS" "$BAM"
    fi

    # Variant calling
    if [[ ! -f "$VCF_GZ" ]]; then
        lofreq call-parallel --pp-threads "$THREADS" \
            --ref data/ref/chrM.fa \
            --out "$VCF" \
            results/${sample}.bam
    fi

    # VCF compression & indexing
    if [[ ! -f "$VCF_TBI" ]]; then
        bgzip -f "$VCF"
        tabix -p vcf "$VCF_GZ"
        rm -f "$VCF"
    fi
done

# Collapse step
COLLAPSED="results/collapsed.tsv"
if [[ ! -f "$COLLAPSED" ]]; then
    {
        printf 'sample\tchrom\tpos\tref\talt\taf\n'
        for sample in "${SAMPLES[@]}"; do
            bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "results/${sample}.vcf.gz"
        done
    } > "$COLLAPSED"
fi