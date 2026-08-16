#!/usr/bin/env bash
set -euo pipefail

mkdir -p results
tmp=$(mktemp)
first=true

for sample in M117-bl M117-ch M117C1-bl M117C1-ch; do
    bam="results/${sample}.bam"
    if [[ ! -f "$bam" ]]; then
        bwa mem data/ref/chrM.fa data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz > "$bam"
        samtools view -bS "$bam" | samtools sort -@4 -o results/${sample}.sorted.bam
        samtools index results/${sample}.sorted.bam
        mv results/${sample}.sorted.bam "$bam"
    fi

    vcf="results/${sample}.vcf.gz"
    if [[ ! -f "$vcf" ]]; then
        bcftools view -Oz "$bam" > "$vcf"

        if $first; then
            bcftools maketable -Oz -o /dev/stdout "$vcf" >> "$tmp"
            first=false
        else
            bcftools view -Oz "$bam" > "results/${sample}.vcf.gz"
            bcftools maketable -Oz -o /dev/stdout "results/${sample}.vcf.gz" | tail -n +2 >> "$tmp"
        fi
    fi
done

if [[ ! -s results/collapsed.tsv ]]; then echo "sample\tchrom\tpos\tref\talt\taf" > results/collapsed.tsv; fi
cat "$tmp" >> results/collapsed.tsv
rm "$tmp"