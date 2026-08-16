#!/usr/bin/env bash
set -euo pipefail

THREADS=4
REF=data/ref/chrM.fa
RAW_DIR=data/raw
RESULTS=results

mkdir -p "$RESULTS"

if [ ! -f "${REF}.bwt" ]; then
    bwa index "$REF"
fi

samples=(M117-bl M117-ch M117C1-bl M117C1-ch)

for sample in "${samples[@]}"; do
    bam="${RESULTS}/${sample}.bam"
    bai="${RESULTS}/${sample}.bam.bai"
    vcf="${RESULTS}/${sample}.vcf.gz"
    tbi="${RESULTS}/${sample}.vcf.gz.tbi"

    if [ -f "$bam" ] && [ -f "$bai" ] && [ -f "$vcf" ] && [ -f "$tbi" ]; then
        continue
    fi

    bwa mem -t "$THREADS" "$REF" "${RAW_DIR}/${sample}_1.fq.gz" "${RAW_DIR}/${sample}_2.fq.gz" | \
        samtools sort -@ "$THREADS" -o "$bam"

    samtools index "$bam"

    lofreq call -f "$REF" -b "$bam" | bcftools view -Oz -o "$vcf"
    tabix -p vcf "$vcf"
done

collapsed="${RESULTS}/collapsed.tsv"
if [ ! -f "$collapsed" ]; then
    echo -e "sample\tchrom\tpos\tref\talt\taf" > "$collapsed"
    for sample in "${samples[@]}"; do
        vcf="${RESULTS}/${sample}.vcf.gz"
        if [ -s "$vcf" ]; then
            bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t[%AF]\n' "$vcf" | awk -v s="$sample" '{print s"\t"$0}' >> "$collapsed"
        fi
    done
fi

exit 0