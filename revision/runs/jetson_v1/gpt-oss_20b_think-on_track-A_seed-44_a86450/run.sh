#!/usr/bin/env bash
set -euo pipefail

THREADS=4
samples=(M117-bl M117-ch M117C1-bl M117C1-ch)

mkdir -p results

ref_fa=data/ref/chrM.fa
if [ ! -f "${ref_fa}.fai" ] || [ ! -f "${ref_fa}.bwt" ]; then
    samtools faidx "$ref_fa"
    bwa index "$ref_fa"
fi

for sample in "${samples[@]}"; do
    raw1=data/raw/${sample}_1.fq.gz
    raw2=data/raw/${sample}_2.fq.gz
    bam=results/${sample}.bam
    bai=results/${sample}.bam.bai
    vcf_uncompressed=results/${sample}.vcf
    vcf_gz=results/${sample}.vcf.gz
    tbi=results/${sample}.vcf.gz.tbi

    if [ ! -s "$bam" ]; then
        bwa mem -t "$THREADS" \
            -R "@RG\\tID:${sample}\\tSM:${sample}\\tLB:${sample}\\tPL:ILLUMINA" \
            "$ref_fa" "$raw1" "$raw2" | samtools sort -@ "$THREADS" -o "$bam"
    fi

    if [ ! -s "$bai" ]; then
        samtools index -@ "$THREADS" "$bam"
    fi

    if [ ! -s "$vcf_gz" ]; then
        lofreq call-parallel --pp-threads "$THREADS" \
            -f "$ref_fa" -b "$bam" -o "$vcf_uncompressed"
        bgzip -c "$vcf_uncompressed" > "$vcf_gz"
        tabix -p vcf "$vcf_gz"
        rm -f "$vcf_uncompressed"
    fi
done

collapsed=results/collapsed.tsv
needs_collapse=false
for sample in "${samples[@]}"; do
    vcf_gz=results/${sample}.vcf.gz
    if [ ! -s "$collapsed" ] || [ "$vcf_gz" -nt "$collapsed" ]; then
        needs_collapse=true
        break
    fi
done

if $needs_collapse; then
    rm -f "$collapsed"
    printf "sample\tchrom\tpos\tref\talt\taf\n" > "$collapsed"
    for sample in "${samples[@]}"; do
        vcf_gz=results/${sample}.vcf.gz
        bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "$vcf_gz" >> "$collapsed"
    done
fi

exit 0