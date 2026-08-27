#!/usr/bin/env bash
set -euo pipefail

THREADS=4
samples=(M117-bl M117-ch M117C1-bl M117C1-ch)

mkdir -p results

# Reference indexing (once)
if [[ ! -f data/ref/chrM.fa.fai ]]; then
    samtools faidx data/ref/chrM.fa
fi
if [[ ! -f data/ref/chrM.fa.amb ]]; then
    bwa index data/ref/chrM.fa
fi

# Per-sample processing loop
for sample in "${samples[@]}"; do
    # Alignment
    if [[ ! -f results/"${sample}".bam ]]; then
        bwa mem -t 4 \
            -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
            data/ref/chrM.fa \
            data/raw/${sample}_1.fq.gz \
            data/raw/${sample}_2.fq.gz |
        samtools sort -@ 4 -o results/"${sample}".bam
    fi

    # BAM indexing
    if [[ ! -f results/"${sample}".bam.bai ]]; then
        samtools index -@ 4 results/"${sample}".bam
    fi

    # Variant calling with lofreq call-parallel
    if [[ ! -f results/"${sample}".vcf.gz ]]; then
        lofreq call-parallel --pp-threads 4 \
            --ref data/ref/chrM.fa \
            --out results/"${sample}".vcf \
            data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz
    fi

    # Compression and indexing
    if [[ ! -f results/"${sample}".vcf.gz.tbi ]]; then
        bgzip -c results/"${sample}".vcf > results/"${sample}".vcf.gz
        tabix -p vcf results/"${sample}".vcf.gz
        rm -f results/"${sample}".vcf
    fi
done

# Collapse step
collapsed_tsv=results/collapsed.tsv
if [[ ! -s "${collapsed_tsv}" || data/ref/chrM.fa -nt "${collapsed_tsv}" ]]; then
    {
        printf "sample\tchrom\tpos\tref\talt\taf\n"
        for sample in "${samples[@]}"; do
            bcftools query -f '{sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' results/"${sample}".vcf.gz
        done
    } | bgzip > "${collapsed_tsv}.gz"
    tabix -p vcf "${collapsed_tsv}.gz"  # index the gzipped TSV for future checks (not required by spec)
    mv "${collapsed_tsv}.gz" "${collapsed_tsv}"
fi

exit 0