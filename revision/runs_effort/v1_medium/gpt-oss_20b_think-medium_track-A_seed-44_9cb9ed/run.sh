#!/usr/bin/env bash
set -euo pipefail

THREADS=4
samples=(M117-bl M117-ch M117C1-bl M117C1-ch)

mkdir -p results

ref="data/ref/chrM.fa"

# Reference indexing
if [[ ! -f "${ref}.amb" || ! -f "${ref}.ann" || ! -f "${ref}.bwt" || ! -f "${ref}.pac" || ! -f "${ref}.sa" ]]; then
    bwa index "$ref"
fi

if [[ ! -f "${ref}.fai" ]]; then
    samtools faidx "$ref"
fi

# Per-sample processing
for sample in "${samples[@]}"; do
    fastq1="data/raw/${sample}_1.fq.gz"
    fastq2="data/raw/${sample}_2.fq.gz"
    bam="results/${sample}.bam"
    bai="results/${sample}.bam.bai"
    vcf_uncompressed="results/${sample}.vcf"
    vcf_gz="results/${sample}.vcf.gz"
    tbi="results/${sample}.vcf.gz.tbi"

    # Alignment
    if [[ ! -s "$bam" || $fastq1 -nt "$bam" || $fastq2 -nt "$bam" ]]; then
        bwa mem -t "$THREADS" -R "@RG\tID:$sample\tSM:$sample\tLB:$sample\tPL:ILLUMINA" \
            "$ref" "$fastq1" "$fastq2" | samtools sort -@ "$THREADS" -o "$bam"
    fi

    # BAM indexing
    if [[ ! -s "$bai" || $bam -nt "$bai" ]]; then
        samtools index -@ "$THREADS" "$bam"
    fi

    # Variant calling
    if [[ ! -s "$tbi" || $bam -nt "$tbi" ]]; then
        lofreq call-parallel --pp-threads "$THREADS" -f "$ref" -b "$bam" > "$vcf_uncompressed"
        bgzip -c "$vcf_uncompressed" > "$vcf_gz"
        tabix -p vcf "$vcf_gz"
        rm -f "$vcf_uncompressed"
    fi
done

# Collapse VCFs into a single TSV
collapsed="results/collapsed.tsv"
need_collapse=0
for sample in "${samples[@]}"; do
    vcf_gz="results/${sample}.vcf.gz"
    if [[ ! -s "$collapsed" || $vcf_gz -nt "$collapsed" ]]; then
        need_collapse=1
        break
    fi
done

if (( need_collapse )); then
    tmpfile=$(mktemp)
    printf "sample\tchrom\tpos\tref\talt\taf\n" > "$tmpfile"
    for sample in "${samples[@]}"; do
        vcf_gz="results/${sample}.vcf.gz"
        bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "$vcf_gz" >> "$tmpfile"
    done
    mv "$tmpfile" "$collapsed"
fi

exit 0