#!/usr/bin/env bash
set -euo pipefail

THREADS=4
samples=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

mkdir -p results

ref="data/ref/chrM.fa"
if [ ! -f "${ref}.bwt" ]; then
    samtools faidx "$ref"
    bwa index "$ref"
fi

for sample in "${samples[@]}"; do
    fq1="data/raw/${sample}_1.fq.gz"
    fq2="data/raw/${sample}_2.fq.gz"
    bam="results/${sample}.bam"

    if [ ! -f "$bam" ]; then
        bwa mem -t "$THREADS" \
            -R "@RG\\tID:${sample}\\tSM:${sample}\\tLB:${sample}\\tPL:ILLUMINA" \
            "$ref" "$fq1" "$fq2" | samtools sort -@ "$THREADS" -o "$bam"
    fi

    bai="${bam}.bai"
    if [ ! -f "$bai" ]; then
        samtools index -@ "$THREADS" "$bam"
    fi

    vcf="results/${sample}.vcf.gz"
    tbi="${vcf}.tbi"

    if [ ! -f "$tbi" ]; then
        tmp_vcf="results/${sample}.vcf"
        lofreq call-parallel --pp-threads "$THREADS" -f "$ref" -o "$tmp_vcf" "$bam"
        bgzip -c "$tmp_vcf" > "$vcf"
        tabix -p vcf "$vcf"
        rm -f "$tmp_vcf"
    fi
done

collapsed="results/collapsed.tsv"
need_rebuild=false
if [ ! -f "$collapsed" ]; then
    need_rebuild=true
else
    for sample in "${samples[@]}"; do
        if [ "$(find results/${sample}.vcf.gz -newer "$collapsed")" ]; then
            need_rebuild=true
            break
        fi
    done
fi

if $need_rebuild; then
    header="sample\tchrom\tpos\tref\talt\taf"
    printf "%s\n" "$header" > "$collapsed"
    for sample in "${samples[@]}"; do
        bcftools query -f "${sample}\\t%CHROM\\t%POS\\t%REF\\t%ALT\\t%INFO/AF\\n" "results/${sample}.vcf.gz" >> "$collapsed"
    done
fi

exit 0