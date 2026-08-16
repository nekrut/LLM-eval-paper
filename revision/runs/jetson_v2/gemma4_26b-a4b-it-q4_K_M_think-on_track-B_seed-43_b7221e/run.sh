#!/usr/bin/env bash
set -euo pipefail

mkdir -p results

samples=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
ref="data/ref/chrM.fa"

if [[ ! -f "${ref}.bwt" ]]; then
    bwa index "$ref"
fi

if [[ ! -t -f "${ref}.fai" ]]; then
    samtools faidx "$ref"
fi

for s in "${samples[@]}"; do
    vcf_gz="results/${s}.vcf.gz"
    bam="results/${s}.bam"
    
    if [[ -f "$vcf_gz" ]]; then
        continue
    fi

    r1="data/raw/${s}_1.fq.gz"
    r2="data/raw/${s}_2.fq.gz"

    bwa mem -t 4 "$ref" "$r1" "$r2" | samtools sort -@ 4 -o "$bam"
    samtools index "$bam"
    
    vcf_uncompressed="results/${s}.vcf"
    lofreq call -f "$ref" -o "$vcf_uncompressed" "$bam"
    
    bcftools view -Oz -o "$vcf_gz" "$vcf_uncompressed"
    tabix -p vcf "$vcf_gz"
    
    rm "$vcf_uncompressed"
done

echo -e "sample\tchrom\tpos\tref\talt\taf" > results/collapsed.tsv
for vcf in results/*.vcf.gz; do
    if [[ -f "$vcf" ]]; then
        s_name=$(basename "$vcf" .vcf.gz)
        bcftools query -f "$s_name\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "$vcf" >> results/collapsed.tsv
    fi
done

exit 0