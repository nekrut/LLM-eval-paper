#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
REF="data/ref/GRCh38_chrM/rCRS.fa"

mkdir -p results

[[ -f "${REF}.bwt" ]] || bwa index "$REF"
[[ -f "${REF}.fai" ]] || samtools faidx "$REF"

for sample in "${SAMPLES[@]}"; do
    RAW1="data/raw/${sample}_1.fq.gz"
    RAW2="data/raw/${sample}_2.fq.gz"
    BAM="results/${sample}.bam"
    BAI="results/${sample}.bam.bai"
    VCF="results/${sample}.vcf"
    VCFZ="results/${sample}.vcf.gz"
    TBZ="results/${sample}.vcf.gz.tbi"

    if [[ ! -f "$BAM" ]]; then
        bwa mem -t "$THREADS" -R "@RG\\tID:${sample}\\tSM:${sample}\\tLB:${sample}\\tPL:ILLUMINA" \
            "$REF" "$RAW1" "$RAW2" | samtools sort -@ "$THREADS" -o "$BAM" -
    fi

    if [[ ! -f "$BAI" ]]; then
        samtools index -@ "$THREADS" "$BAM"
    fi

    if [[ ! -f "$VCF" && ! -f "$VCFZ" ]]; then
        lofreq call-parallel --pp-threads "$THREADS" -f "$REF" -o "$VCF" "$BAM"
    fi

    if [[ ! -f "$TBZ" ]]; then
        bcftools view -O z -o "$VCFZ" "$VCF"
        rm "$VCF"
        tabix -p vcf "$VCFZ"
    fi
done

printf 'sample\tchrom\tpos\tref\talt\taf\n' > results/collapsed.tsv
for sample in "${SAMPLES[@]}"; do
    bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "results/${sample}.vcf.gz" | \
        awk -v s="$sample" 'BEGIN{OFS="\t"}{print s,$0}' >> results/collapsed.tsv
done