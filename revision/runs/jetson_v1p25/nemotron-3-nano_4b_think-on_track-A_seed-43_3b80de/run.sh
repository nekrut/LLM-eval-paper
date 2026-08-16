#!/usr/ bin/env bash
set -euo pipefail

THREADS=4
samples="M117-bl M117-ch M117C1-bl M117C1-ch"
results_dir="results"

mkdir -p "$results_dir"

# Reference index
if [ ! -f chrM.fa.fai ] || [ ! -f .amb ] || [ ! -f .ann ] || [ ! -f .bwt ] || [ ! -f .pac ] || [ ! -f .sa ]; then
    samtools faidx data/ref/chrM.fa > /dev/null 2>&1
    bwa index data/ref/chrM.fa > /dev/null 2>&1
fi

# Per-sample processing
for sample in $samples; do
    bam="results/${sample}.bam"
    vcf_gz="results/${sample}.vcf.gz"
    vcf_tbi="results/${sample}.vcf.gz.tbi"

    # Skip if VCF already indexed and newer than BAM
    if [ -f "$vcf_tbi" ] && [ $(stat -c %Y "$vcf_tbi") -ge $(stat -c %Y "$bam") ]; then
        continue
    fi

    # Align & sort
    bwa mem -t $THREADS data/raw/${sample}_1. fq.gz data/raw/${sample}_2.fq.gz \
        -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" | samtools sort -@ $THREADS -o "$bam"

    # Index BAM
    samtools index -@ $THREADS "$bam"

    # Variant calling
    lofreq call-parallel --pp-threads 4 -f data/ref/chrM.fa -o results/${sample}.vcf "$bam" > /dev/null

    # Compress & index VCF
    bgzip "$vcf_gz"
    tabix -p vcf "$vcf_tbi"
    rm "$results/${sample}.vcf"

done

# Collapse step
if [ ! -f results/collapsed.tsv ] || \
   [ $(stat -c %Y results/*.vcf.gz | sort -k1,2 -r | head -n1) -lt $(stat -c %Y results/collapsed.tsv) ]; then

    # Build collapsed TSV
    > results/collapsed.tsv
    for sample in $samples; do
        bcftools query -f '{sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' \
            "results/${sample}.vcf.gz" >> results/collapsed.tsv
    done

    # Prepend header
    ed -s results/collapsed.tsv <<< $'\n sample\tchrom\tpos\tref\talt\taf'
fi

exit 0