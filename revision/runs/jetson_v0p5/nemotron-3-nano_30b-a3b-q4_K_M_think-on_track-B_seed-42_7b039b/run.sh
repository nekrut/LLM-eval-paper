#!/usr/bin/env bash
set -euo pipefail

if [[ -f results/collapsed.tsv ]]; then exit 0; fi

mkdir -p results
samples=()
for f in data/raw/*_1.fq.gz; do
    sample=$(basename "$f")
    sample=${sample%_1.fq.gz}
    samples+=("$sample")
done
THREADS=${THREADS:-4}
for sample in "${samples[@]}"; do
    if [[ -f results/${sample}.vcf.gz.tbi ]]; then continue; fi
    bwa mem -t "$THREADS" data/ref/chrM.fa \
        data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz |
    samtools view -bS -o results/${sample}.bam
    samtools index results/${sample}.bam
    bcftools mpileup -f data/ref/chrM.fa -Ou results/${sample}.bam |
    bcftools call -c -Oz -o results/${sample}.vcf.gz
    tabix -p vcf results/${sample}.vcf.gz
done
{
    printf "sample\tchrom\tpos\tref\talt\taf\n"
    for sample in "${samples[@]}"; do
        if [[ -f results/${sample}.vcf.gz.tbi ]]; then
            while IFS=$'\t' read -r chrom pos ref alt af; do
                printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$sample" "$chrom" "$pos" "$ref" "$alt" "$af"
            done < <(bcftools query -f '%CHROM\t%POS\t%REF\t%ALT[\t%AF]\n' results/${sample}.vcf.gz)
        fi
    done
} > results/collapsed.tsv