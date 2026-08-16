#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)
mkdir -p results

# Reference indexing (once)
if [ ! -f data/ref/chrM.fa.fai ] || [ ! -f data/ref/chrM.fa.bwt ]; then
    samtools faidx data/ref/chrM.fa
    bwa index data/ref/chrM.fa
fi

for sample in "${SAMPLES[@]}"; do
    if [ -f "results/${sample}.vcf.gz.tbi" ]; then
        continue
    fi

    # Alignment & Sort
    bwa mem -t ${THREADS} -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
        data/ref/chrM.fa "data/raw/${sample}_1.fq.gz" "data/raw/${sample}_2.fq.gz" | \
        samtools sort -@ ${THREADS} -o "results/${sample}.bam"

    # BAM Indexing
    samtools index -@ ${THREADS} "results/${sample}.bam"

    # Variant Calling
    lofreq call-parallel --pp-threads ${THREADS} --ref data/ref/chrM.fa \
        --out "results/${sample}.vcf" "results/${sample}.bam"

    # VCF Compression & Indexing
    bgzip "results/${sample}.vcf"
    tabix -p vcf "results/${sample}.vcf.gz"
    rm -f "results/${sample}.vcf"
done

# Collapse to TSV
if [ ! -f results/collapsed.tsv ]; then
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > results/collapsed.tsv
    for sample in "${SAMPLES[@]}"; do
        bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" \
            "results/${sample}.vcf.gz" >> results/collapsed.tsv
    done
fi