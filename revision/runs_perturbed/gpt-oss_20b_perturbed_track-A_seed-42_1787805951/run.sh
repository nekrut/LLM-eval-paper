#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

REF="data/ref/GRCh38_chrM/rCRS.fa"

mkdir -p results

[[ -f "${REF}.bwt" ]] || bwa index "$REF"
[[ -f "${REF}.fai" ]] || samtools faidx "$REF"

for sample in "${SAMPLES[@]}"; do
    bam="results/${sample}.bam"
    [[ -f "$bam" ]] || {
        bwa mem -t "$THREADS" \
            -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
            "$REF" "data/raw/${sample}_1.fq.gz" "data/raw/${sample}_2.fq.gz" |
        samtools sort -@ "$THREADS" -o "$bam" -
    }

    bai="results/${sample}.bam.bai"
    [[ -f "$bai" ]] || samtools index -@ "$THREADS" "$bam"

    vcf_uncompressed="results/${sample}.vcf"
    [[ -f "$vcf_uncompressed" || -f "${vcf_uncompressed}.gz" ]] || \
        lofreq call-parallel --pp-threads "$THREADS" -f "$REF" -o "$vcf_uncompressed" "$bam"

    vcf_gz="results/${sample}.vcf.gz"
    tbi="${vcf_gz}.tbi"
    [[ -f "$tbi" ]] || {
        bcftools view -Oz -o "$vcf_gz" "$vcf_uncompressed"
        tabix -p vcf "$vcf_gz"
    }
done

printf 'sample\tchrom\tpos\tref\talt\taf\n' > results/collapsed.tsv
for sample in "${SAMPLES[@]}"; do
    bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "results/${sample}.vcf.gz" |
        awk -v s="$sample" 'BEGIN{OFS="\t"}{print s,$0}' >> results/collapsed.tsv
done