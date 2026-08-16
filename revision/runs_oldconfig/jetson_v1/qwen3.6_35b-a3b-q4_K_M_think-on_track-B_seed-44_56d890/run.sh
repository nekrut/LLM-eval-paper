#!/usr/bin/env bash
set -euo pipefail

mkdir -p results

REF="data/ref/chrM.fa"
if [[ ! -f "${REF}.fai" ]]; then
    samtools faidx "$REF"
fi

SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)

for sample in "${SAMPLES[@]}"; do
    bam="results/${sample}.bam"
    vcf="results/${sample}.vcf.gz"
    tbi="${vcf}.tbi"

    if [[ -f "$tbi" ]]; then
        continue
    fi

    bwa mem -t 4 "$REF" \
        "data/raw/${sample}_1.fq.gz" \
        "data/raw/${sample}_2.fq.gz" | \
    samtools sort -@ 4 -o "$bam" -

    samtools index "$bam"

    bcftools mpileup -f "$REF" -a FORMAT/AD,FORMAT/DP "$bam" | \
    bcftools call -mv -Ov -o - --ploidy 1 - | \
    bcftools sort -O z -o "$vcf" -

    tabix "$vcf"
done

printf 'sample\tchrom\tpos\tref\talt\taf\n' > results/collapsed.tsv
for sample in "${SAMPLES[@]}"; do
    vcf="results/${sample}.vcf.gz"
    [[ -f "$vcf" ]] || continue
    bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "$vcf" | \
    awk -F'\t' '{if($5=="") $5="."; print}' >> results/collapsed.tsv
done