#!/usr/bin/env bash
set -euo pipefail

THREADS=${THREADS:-4}

SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

mkdir -p results

[[ -f data/ref/chrM.fa.bwt ]] || bwa index data/ref/chrM.fa
[[ -f data/ref/chrM.fa.fai ]] || samtools faidx data/ref/chrM.fa

for sample in "${SAMPLES[@]}"; do
    bam="results/${sample}.bam"
    bai="results/${sample}.bam.bai"
    vcf_gz="results/${sample}.vcf.gz"
    tbi="results/${sample}.vcf.gz.tbi"

    if [[ ! -f "$bam" ]]; then
        bwa mem -t "$THREADS" data/ref/chrM.fa \
            "data/raw/${sample}_1.fq.gz" \
            "data/raw/${sample}_2.fq.gz" | \
            samtools sort -@ "$THREADS" -o "$bam"
    fi

    [[ -f "$bai" ]] || samtools index "$bam"

    if [[ ! -f "$vcf_gz" ]]; then
        lofreq call --bams "$bam" -f data/ref/chrM.fa \
            --min-qual 20 --min-af 0.01 --call-indels | \
            bgzip > "$vcf_gz"
    fi

    [[ -f "$tbi" ]] || tabix -p vcf "$vcf_gz"
done

if [[ ! -f results/collapsed.tsv ]]; then
    printf "sample\tchrom\tpos\tref\talt\taf\n" > results/collapsed.tsv

    for sample in "${SAMPLES[@]}"; do
        bcftools query -f '%CHROM\t%POS\t%REF\t%ALT[\t%INFO/AF\n]' \
            "results/${sample}.vcf.gz" | \
            awk -v s="$sample" 'BEGIN{OFS="\t"} {print s, $1, $2, $3, $4, $5}' \
            >> results/collapsed.tsv
    done
fi