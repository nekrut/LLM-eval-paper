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
        bwa mem -t "$THREADS" \
            -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
            data/ref/chrM.fa \
            data/raw/${sample}_1.fq.gz \
            data/raw/${sample}_2.fq.gz |
        samtools sort -@ "$THREADS" -o results/"${sample}".bam
    fi

    # BAM indexing
    if [[ ! -f results/"${sample}".bam.bai ]]; then
        samtools index -@ "$THREADS" results/"${sample}".bam
    fi

    # Variant calling with lofreq (skip if VCF.gz.tbi exists)
    if [[ ! -f results/"${sample}".vcf.gz.tbi ]]; then
        lofreq call-parallel --pp-threads "$THREADS" \
            --ref data/ref/chrM.fa \
            --out results/"${sample}".vcf \
            --sig \
            --bonf \
            results/"${sample}".bam

        bgzip -c results/"${sample}".vcf > results/"${sample}".vcf.gz
        tabix -p vcf results/"${sample}".vcf.gz
        rm -f results/"${sample}".vcf
    fi
done

# Collapse step: generate collapsed.tsv if any VCF is newer
if [[ ! -f results/collapsed.tsv || results/collapsed.tsv -nt data/ref/chrM.fa ]]; then
    {
        printf "sample\tchrom\tpos\tref\talt\taf\n"
        for sample in "${samples[@]}"; do
            bcftools query -f '{sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' results/"${sample}".vcf.gz
        done
    } > results/collapsed.tsv
}