#!/usr/bin/env bash
set -euo pipefail

THREADS=4
REF="data/ref/chrM.fa"
RAW="data/raw"
RESULTS="results"

mkdir -p "$RESULTS"

if [[ ! -f "${REF}.bwt" ]]; then
    bwa index "$REF"
fi

samples=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

for sample in "${samples[@]}"; do
    bam="${RESULTS}/${sample}.bam"
    bai="${RESULTS}/${sample}.bam.bai"
    vcf="${RESULTS}/${sample}.vcf.gz"
    vcf_tbi="${RESULTS}/${sample}.vcf.gz.tbi"
    
    if [[ -f "$bam" && -f "$bai" && -f "$vcf" && -f "$vcf_tbi" ]]; then
        continue
    fi
    
    fq1="${RAW}/${sample}_1.fq.gz"
    fq2="${RAW}/${sample}_2.fq.gz"
    
    bwa mem -t "$THREADS" "$REF" "$fq1" "$fq2" | \
        samtools sort -@ "$THREADS" -o "$bam" -
    
    samtools index "$bam"
    
    lofreq call -d "$bam" --pp-threads "$THREADS" -f "$REF" -o "${vcf%.gz}" "$bam"
    
    bcftools view -Oz -o "$vcf" "${vcf%.gz}"
    tabix -p vcf "$vcf"
done

collapsed="${RESULTS}/collapsed.tsv"
if [[ ! -f "$collapsed" ]]; then
    echo -e "sample\tchrom\tpos\tref\talt\taf" > "$collapsed"
    
    for sample in "${samples[@]}"; do
        vcf="${RESULTS}/${sample}.vcf.gz"
        bcftools query -f '%CHROM\t%POS\t%REF\t[%ALT]\n' "$vcf" | \
            while IFS=$'\t' read -r chrom pos ref alt; do
                if [[ -n "$alt" ]]; then
                    af=$(bcftools query -f '[%AF]\n' "$vcf" | head -1)
                    echo -e "${sample}\t${chrom}\t${pos}\t${ref}\t${alt}\t${af}"
                fi
            done >> "$collapsed"
    done
fi

exit 0