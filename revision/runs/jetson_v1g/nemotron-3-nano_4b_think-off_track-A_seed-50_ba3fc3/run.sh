#!/usr/bin/env bash
set -euo pipefail
THREADS=4
SAMPLES="M117-bl M117-ch M117C1-bl M117C1-ch"
mkdir -p results

# Index chrM if not already indexed
if [[ ! -f "data/ref/chrM.fa.ind" ]]; then
    samtools faidx data/ref/chrM.fa
fi
if [[ ! -f "data/ref/chrM.amb" ]] && [[ -f "data/ref/chrM.anq" ]] && [[ -f "data/ref/chrM.bwt" ]] && [[ -f "data/ref/chrM.pac" ]] && [[ -f "data/ref/chrM.sa" ]]; then
    bwa index data/ref/chrM.fa
fi

# Per-sample processing
for sample in $SAMPLES; do
    # Skip if all outputs exist and are up to date
    if [[ -f "results/${sample}.vcf.gz.tbi" ]] && [[ -f "results/${sample}.bam.bai" ]] && \
       ( [ "$(stat -c %Y results/${sample}.vcf.gz.tbi)" -le "$(stat -c %Y data/raw/${sample}_1.fq.gz)" ] && 
         [ "$(stat -c %Y results/${sample}.vcf.gz.tbi)" -le "$(stat -c %Y data/raw/${sample}_2.fq.gz)" ] ); then
        continue
    fi

    # Alignment
    bwa mem -t $THREADS "data/ref/chrM.fa" "data/raw/${sample}_1.fq.gz" "data/raw/${sample}_2.fq.gz" \
      -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA"

    # Sort BAM
    samtools sort -@ $THREADS -o results/${sample}.bam "data/raw/${sample}_1.fq.gz" "data/raw/${sample}_2.fq.gz"

    # Index BAM
    samtools index -@ $THREADS results/${sample}.bam

    # Variant calling with lofreq call-parallel
    lofreq call-parallel --pp-threads 4 --verbose \
        --ref data/ref/chrM.fa --out results/${sample}.vcf \
        --sig \
        --bonf \
        results/${sample}.bam

    # Compress VCF and index
    bgzip -@ $THREADS results/${sample}.vcf
    tabix -p vcf -@ $THREADS results/${sample}.vcf.gz
    rm results/${sample}.vcf

done

# Collapse TSV
if [[ ! -f "results/collapsed.tsv" ]] || \
   ( [ "$(stat -c %Y results/collapsed.tsv)" -lt "$(stat -c %Y data/raw/M117-bl_1.fq.gz)" ] ] ||
   ( [ "$(stat -c %Y results/collapsed.tsv)" -lt "$(stat -c %Y data/raw/M117-bl_2.fq.gz)" ] ) ||
   ( [ "$(stat -c %Y results/collapsed.tsv)" -lt "$(stat -c %Y data/raw/M117-ch_1.fq.gz)" ] ] ||
   ( [ "$(stat -c %Y results/collapsed.tsv)" -lt "$(stat -c %Y data/raw/M117-ch_2.fq.gz)" ] ) ||
   ( [ "$(stat -c %Y results/collapsed.tsv)" -lt "$(stat -c %Y data/raw/M117C1-bl_1.fq.gz)" ] ] ||
   ( [ "$(stat -c %Y results/collapsed.tsv)" -lt "$(stat -c %Y data/raw/M117C1-bl_2.fq.gz)" ] ) ||
   ( [ "$(stat -c %Y results/collapsed.tsv)" -lt "$(stat -c %Y data/raw/M117C1-ch_1.fq.gz)" ] ] ||
   ( [ "$(stat -c %Y results/collapsed.tsv)" -lt "$(stat -c %Y data/raw/M117C1-ch_2.fq.gz)" ] )); then

    echo "sample\tchrom\tpos\tref\talt\taf" > results/collapsed.tsv
    for sample in $SAMPLES; do
        bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "results/${sample}.vcf.gz" >> results/collapsed.tsv
    done

fi