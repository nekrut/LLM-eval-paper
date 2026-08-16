#!/usr/bin/env bash
set -euo pipefail

THREADS=4
samples=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
mkdir -p results

ref="data/ref/chrM.fa"
if [ ! -f "${ref}.fai" ]; then
    samtools faidx "$ref"
fi
if [ ! -f "${ref}.amb" ]; then
    bwa index "$ref"
fi

for sample in "${samples[@]}"; do
    bam="results/${sample}.bam"
    bai="${bam}.bai"
    vcf="results/${sample}.vcf"
    vcf_gz="results/${sample}.vcf.gz"
    tbi="results/${sample}.vcf.gz.tbi"

    if [ ! -f "$bam" ] || \
       [[ $(stat -c %Y data/raw/${sample}_1.fq.gz) -gt $(stat -c %Y "$bam") ]] || \
       [[ $(stat -c %Y data/raw/${sample}_2.fq.gz) -gt $(stat -c %Y "$bam") ]]; then
        bwa mem -t "$THREADS" -R "@RG\\tID:${sample}\\tSM:${sample}\\tLB:${sample}\\tPL:ILLUMINA" \
            data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz | \
        samtools sort -@ "$THREADS" -o "$bam"
    fi

    if [ ! -f "$bai" ] || [[ $(stat -c %Y "$bam") -gt $(stat -c %Y "$bai") ]]; then
        samtools index -@ "$THREADS" "$bam"
    fi

    if [ ! -f "$tbi" ] || [[ $(stat -c %Y "$bam") -gt $(stat -c %Y "$tbi") ]]; then
        lofreq call-parallel --pp-threads "$THREADS" --verbose \
            --ref "$ref" --out "$vcf" --sig --bonf "$bam"
        bgzip -c "$vcf" > "$vcf_gz"
        tabix -p vcf "$vcf_gz"
        rm "$vcf"
    fi
done

tsv="results/collapsed.tsv"
latest=0
for sample in "${samples[@]}"; do
    vcf_gz="results/${sample}.vcf.gz"
    if [ -f "$vcf_gz" ]; then
        mtime=$(stat -c %Y "$vcf_gz")
        (( mtime > latest )) && latest=$mtime
    fi
done

if [ ! -f "$tsv" ] || [[ $(stat -c %Y "$tsv") -lt $latest ]]; then
    printf "sample\tchrom\tpos\tref\talt\taf\n" > "$tsv"
    for sample in "${samples[@]}"; do
        bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" results/${sample}.vcf.gz >> "$tsv"
    done
fi