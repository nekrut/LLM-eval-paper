#!/usr/bin/env bash
set -euo pipefail

THREADS=4
samples=(M117-bl M117-ch M117C1-bl M117C1-ch)

mkdir -p results

# Reference indexing (once)
if [ ! -f data/ref/chrM.fa.fai ]; then
    samtools faidx data/ref/chrM.fa
fi

if [ ! -f data/ref/chrM.fa.bwt ]; then
    bwa index data/ref/chrM.fa
fi

# Per-sample processing
for sample in "${samples[@]}"; do
    bam_file="results/${sample}.bam"
    bai_file="${bam_file}.bai"
    vcf_gz="results/${sample}.vcf.gz"
    tbi_vcf="${vcf_gz}.tbi"

    fq1="data/raw/${sample}_1.fq.gz"
    fq2="data/raw/${sample}_2.fq.gz"

    # Alignment step: check BAM and BAI existence
    need_align=0
    if [ ! -f "$bam_file" ] || [ ! -f "$bai_file" ]; then
        need_align=1
    fi

    if [ $need_align -eq 1 ]; then
        bwa mem -t ${THREADS} \
            -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
            data/ref/chrM.fa \
            <(zcat "$fq1") <(zcat "$fq2") | \
        samtools sort -@ ${THREADS} -o "$bam_file"
        samtools index -@ ${THREADS} "$bam_file"
    fi

    # Variant calling step: check VCF and TBI existence
    need_vcf=0
    if [ ! -f "$vcf_gz" ] || [ ! -f "$tbi_vcf" ]; then
        need_vcf=1
    elif [ "$bam_file" -nt "$vcf_gz" ]; then
        need_vcf=1
    fi

    if [ $need_vcf -eq 1 ]; then
        tmp_vcf="results/${sample}.vcf"
        lofreq call-parallel --pp-threads ${THREADS} \
            -f data/ref/chrM.fa \
            -o "$tmp_vcf" \
            "$bam_file"
        bgzip -c "$tmp_vcf" > "$vcf_gz"
        tabix -p vcf "$vcf_gz"
        rm -f "$tmp_vcf"
    fi
done

# Collapsed TSV generation
collapsed_tsv="results/collapsed.tsv"
need_collapse=0

if [ ! -f "$collapsed_tsv" ]; then
    need_collapse=1
else
    for sample in "${samples[@]}"; do
        vcf_gz="results/${sample}.vcf.gz"
        if [ "$vcf_gz" -nt "$collapsed_tsv" ]; then
            need_collapse=1
            break
        fi
    done
fi

if [ $need_collapse -eq 1 ]; then
    echo -e "sample\tchrom\tpos\tref\talt\taf" > "$collapsed_tsv"
    for sample in "${samples[@]}"; do
        bcftools query \
            -f '{sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' \
            "results/${sample}.vcf.gz" >> "$collapsed_tsv"
    done
fi