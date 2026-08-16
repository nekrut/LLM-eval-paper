#!/usr/bin/env bash
set -euo pipefail

THREADS=4
samples=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

mkdir -p results

ref="data/ref/chrM.fa"
if [ ! -f "${ref}.fai" ] || [ ! -f "${ref}.bwt" ]; then
    samtools faidx "$ref"
    bwa index "$ref"
fi

for sample in "${samples[@]}"; do
    bam="results/${sample}.bam"
    bai="results/${sample}.bam.bai"
    vcf="${bam%.bam}.vcf.gz"

    if [ ! -s "$bam" ]; then
        bwa mem -t "$THREADS" \
            -R "@RG\\tID:${sample}\\tSM:${sample}\\tLB:${sample}\\tPL:ILLUMINA" \
            data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz |
        samtools sort -@ "$THREADS" -o "$bam"
    fi

    if [ ! -s "$bai" ]; then
        samtools index -@ "$THREADS" "$bam"
    fi

    tbi="${vcf}.tbi"
    if [ ! -s "$tbi" ]; then
        lofreq call-parallel --pp-threads "$THREADS" --verbose \
            --ref "$ref" --out "${bam%.bam}.vcf" \
            --sig --bonf \
            "$bam"

        bcftools view -Oz -o "${bam%.bam}.vcf.gz" "${bam%.bam}.vcf"
        tabix -p vcf "${bam%.bam}.vcf.gz"
        rm "${bam%.bam}.vcf"
    fi
done

collapsed="results/collapsed.tsv"
rebuild=false
if [ ! -s "$collapsed" ]; then
    rebuild=true
else
    for sample in "${samples[@]}"; do
        if [ "$(stat -c %Y results/${sample}.vcf.gz)" -gt "$(stat -c %Y "$collapsed")" ]; then
            rebuild=true
            break
        fi
    done
fi

if $rebuild; then
    tmp=$(mktemp)
    for sample in "${samples[@]}"; do
        bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" results/${sample}.vcf.gz >> "$tmp"
    done
    printf "sample\tchrom\tpos\tref\talt\taf\n" > "$collapsed"
    cat "$tmp" >> "$collapsed"
    rm "$tmp"
fi

exit 0