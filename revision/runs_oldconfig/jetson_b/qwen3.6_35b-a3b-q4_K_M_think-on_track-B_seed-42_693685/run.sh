#!/usr/bin/env bash
set -euo pipefail

SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)
REF="data/ref/chrM.fa"
mkdir -p results

if [ ! -f "${REF}.bwt" ]; then
    bwa index "$REF"
fi
if [ ! -f "${REF}.fai" ]; then
    samtools faidx "$REF"
fi

for sample in "${SAMPLES[@]}"; do
    BAM="results/${sample}.bam"
    VCF="results/${sample}.vcf.gz"

    if [ ! -f "$BAM" ]; then
        bwa mem -t 4 "$REF" "data/raw/${sample}_1.fq.gz" "data/raw/${sample}_2.fq.gz" | \
            samtools sort -@ 4 -o "$BAM" -
    fi

    if [ ! -f "${BAM}.bai" ]; then
        samtools index "$BAM"
    fi

    if [ ! -f "$VCF" ]; then
        bcftools mpileup -f "$REF" -d 1000000 "$BAM" | \
            bcftools call -mv -Oz -o "$VCF" -
    fi

    if [ ! -f "${VCF}.tbi" ]; then
        tabix "$VCF"
    fi
done

COLLAPSED="results/collapsed.tsv"
if [ ! -f "$COLLAPSED" ]; then
    printf "sample\tchrom\tpos\tref\talt\taf\n" > "$COLLAPSED"
    for sample in "${SAMPLES[@]}"; do
        VCF="results/${sample}.vcf.gz"
        if [ -f "$VCF" ]; then
            bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%AF\n' "$VCF" | \
                awk -v s="$sample" 'NF{print s"\t"$0}' >> "$COLLAPSED"
        fi
    done
fi