#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
REF="data/ref/chrM.fa"

mkdir -p results

# 2. Reference indexing (once)
if [[ ! -f data/ref/chrM.fa.fai ]]; then
    samtools faidx "$REF"
fi
if [[ ! -f data/ref/chrM.bwt ]]; then
    bwa index "$REF"
fi

# 3-5. Per-sample alignment, sorting, and indexing
for sample in "${SAMPLES[@]}"; do
    fq1="data/raw/${sample}_1.fq.gz"
    fq2="data/raw/${sample}_2.fq.gz"
    bam="results/${sample}.bam"
    bai="results/${sample}.bam.bai"

    if [[ ! -f "$bai" ]]; then
        bwa mem -t "$THREADS" -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" "$fq1" "$fq2" \
            | samtools sort -@ "$THREADS" -o "$bam"
        samtools index -@ "$THREADS" "$bam"
    fi
done

# 6-7. Variant calling, compression, and indexing
for sample in "${SAMPLES[@]}"; do
    vcf="results/${sample}.vcf"
    vcf_gz="results/${sample}.vcf.gz"
    tbi="results/${sample}.vcf.gz.tbi"

    if [[ ! -f "$tbi" ]]; then
        lofreq call-parallel --pp-threads "$THREADS" -f "$REF" "results/${sample}.bam" -o "$vcf"
        bgzip -c "$vcf" > "$vcf_gz"
        tabix -p vcf "$vcf_gz"
        rm "$vcf"
    fi
done

# 8. Collapse step
COLLAPSED="results/collapsed.tsv"
HEADER="sample\tchrom\tpos\tref\talt\taf"

if [[ ! -f "$COLLAPSED" ]]; then
    {
        echo "$HEADER"
        for sample in "${SAMPLES[@]}"; do
            bcftools query -f '{sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "results/${sample}.vcf.gz"
        done
    } > "$COLLAPSED"
fi