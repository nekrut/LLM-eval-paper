#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)

mkdir -p results

# Reference indexing (once)
if [[ ! -f data/ref/chrM.fa.fai || ! -f data/ref/chrM.fa.bwt ]]; then
    samtools faidx data/ref/chrM.fa
    bwa index data/ref/chrM.fa
fi

for sample in "${SAMPLES[@]}"; do
    bam="results/${sample}.bam"
    bai="${bam}.bai"
    vcf="results/${sample}.vcf"
    vcfz="${vcf}.gz"
    tbix="${vcfz}.tbi"

    # Alignment & sorting
    if [[ ! -f "$bam" ]]; then
        bwa mem -t "$THREADS" \
            "-R @RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
            data/ref/chrM.fa \
            "data/raw/${sample}_1.fq.gz" \
            "data/raw/${sample}_2.fq.gz" | \
        samtools sort -@ "$THREADS" -o "$bam"
    fi

    # BAM indexing
    if [[ ! -f "$bai" ]]; then
        samtools index -@ "$THREADS" "$bam"
    fi

    # Variant calling
    if [[ ! -f "$vcfz" ]]; then
        lofreq call-parallel --pp-threads "$THREADS" \
            --verbose \
            --ref data/ref/chrM.fa \
            --out "$vcf" \
            "$bam"
    fi

    # VCF compression & indexing
    if [[ ! -f "$tbix" ]]; then
        bgzip "$vcf"
        tabix -p vcf "$vcfz"
        rm -f "$vcf"
    fi
done

# Collapse step
collapsed="results/collapsed.tsv"
if [[ ! -f "$collapsed" ]]; then
    {
        printf 'sample\tchrom\tpos\tref\talt\taf\n'
        for sample in "${SAMPLES[@]}"; do
            bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "results/${sample}.vcf.gz"
        done
    } > "$collapsed"
fi