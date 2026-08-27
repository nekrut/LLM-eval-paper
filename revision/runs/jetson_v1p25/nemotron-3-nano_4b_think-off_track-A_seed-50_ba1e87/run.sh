#!/usr/bin/env bash
set -euo pipefail
THREADS=4
SAMPLES="M117-bl M117-ch M117C1-bl M117C1-ch"
mkdir -p results

# Index chrM.fa if not already indexed
if [ ! -f data/ref/chrM.ffai ] || [ data/ref/chrM.ffai -nt data/ref/chrM.fa ]; then
    samtools faidx data/ref/chrM.fa
fi
if [ ! -f data/ref/chrM.amb ] || [ data/ref/chrM.amb -nt data/ref/chrM.ffai ]; then
    bwa index data/ref/chrM.fa
fi

for sample in $SAMPLES; do
    # Skip if all outputs are up to date
    if [ -f "results/${sample}.vcf.gz" ] && [ -f "results/${sample}.bam" ] && \
       [ ! -f "results/${sample}.vcf.gz.tbi" ]; then
        lofreq call-parallel --pp-threads $THREADS -f data/ref/chrM.ffai -o results/${sample}.vcf results/${sample}.bam
    fi

    if [ ! -f "results/${sample}.bam.bai" ] || [ "results/${sample}.bam.bai" -nt "results/${sample}.bam" ]; then
        samtools index -@ $THREADS results/${sample}.bam
    fi

    if [ ! -f "results/${sample}.vcf.gz.tbi" ] || [ "results/${sample}.vcf.gz.tbi" -nt "results/${sample}.vcf.gz" ]; then
        bgzip results/${sample}.vcf > results/${sample}.vcf.gz
        tabix -p vcf results/${sample}.vcf.gz > results/${sample}.vcf.gz.tbi
        rm results/${sample}.vcf
    fi

done

# Collapse variants into results/collapsed.tsv if needed
if [ ! -f "results/collapsed.tsv" ] || [ "results/collapsed.tsv" -nt "results/*.vcf.gz" ]; then
    echo "sample\tchrom\tpos\tref\talt\taf" > results/collapsed.tsv
    for sample in $SAMPLES; do
        bcftools query -f '{sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' results/${sample}.vcf.gz >> results/collapsed.tsv
    done
fi

exit 0