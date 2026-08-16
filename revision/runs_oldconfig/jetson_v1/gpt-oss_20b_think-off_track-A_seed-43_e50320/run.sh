#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

mkdir -p results

REF=data/ref/chrM.fa
if [[ ! -f "${REF}.fai" ]]; then
    samtools faidx "$REF"
fi
if [[ ! -f "${REF}.bwt" ]]; then
    bwa index "$REF"
fi

for sample in "${SAMPLES[@]}"; do
    bam=results/${sample}.bam
    bai=${bam}.bai
    fq1=data/raw/${sample}_1.fq.gz
    fq2=data/raw/${sample}_2.fq.gz

    if [[ -f "$bam" && -f "$bai" && "$bam" -nt "$fq1" && "$bam" -nt "$fq2" ]]; then
        continue
    fi

    bwa mem -t "$THREADS" -R "@RG\\tID:${sample}\\tSM:${sample}\\tLB:${sample}\\tPL:ILLUMINA" \
        "$fq1" "$fq2" | samtools sort -@ "$THREADS" -o "$bam"
    samtools index -@ "$THREADS" "$bam"
done

for sample in "${SAMPLES[@]}"; do
    bam=results/${sample}.bam
    vcf=results/${sample}.vcf.gz
    tbi=${vcf}.tbi
    tmpvcf=results/${sample}.vcf

    if [[ -f "$vcf" && -f "$tbi" && "$vcf" -nt "$bam" ]]; then
        continue
    fi

    lofreq call-parallel --pp-threads "$THREADS" -f data/ref/chrM.fa -o "$tmpvcf" "$bam"
    bgzip -c "$tmpvcf" > "$vcf"
    tabix -p vcf "$vcf"
    rm "$tmpvcf"
done

collapsed=results/collapsed.tsv
needs_rebuild=false
for sample in "${SAMPLES[@]}"; do
    vcf=results/${sample}.vcf.gz
    if [[ ! -f "$collapsed" || "$vcf" -nt "$collapsed" ]]; then
        needs_rebuild=true
        break
    fi
done

if $needs_rebuild; then
    printf "sample\tchrom\tpos\tref\talt\taf\n" > "$collapsed"
    for sample in "${SAMPLES[@]}"; do
        vcf=results/${sample}.vcf.gz
        bcftools query -f "${sample}\\t%CHROM\\t%POS\\t%REF\\t%ALT\\t%INFO/AF\\n" "$vcf" >> "$collapsed"
    done
fi