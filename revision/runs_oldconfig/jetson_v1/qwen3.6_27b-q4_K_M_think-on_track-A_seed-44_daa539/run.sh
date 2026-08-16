#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)
mkdir -p results/

# Reference indexing (idempotent)
if [[ ! -f data/ref/chrM.fa.fai ]]; then
    samtools faidx data/ref/chrM.fa
fi
if [[ ! -f data/ref/chrM.fa.bwt ]]; then
    bwa index data/ref/chrM.fa
fi

# Per-sample processing
for sample in "${SAMPLES[@]}"; do
    # Skip if final VCF index exists (idempotency guard)
    if [[ -f results/${sample}.vcf.gz.tbi ]]; then
        continue
    fi

    # Alignment and sorting
    RG="@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA"
    bwa mem -t $THREADS -R "$RG" data/ref/chrM.fa data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz | \
        samtools sort -@ $THREADS -o results/${sample}.bam

    # BAM indexing
    samtools index -@ $THREADS results/${sample}.bam

    # Variant calling with lofreq call-parallel
    lofreq call-parallel --pp-threads $THREADS -f data/ref/chrM.fa -o results/${sample}.vcf results/${sample}.bam

    # VCF compression and indexing
    bgzip -c results/${sample}.vcf > results/${sample}.vcf.gz
    tabix -p vcf results/${sample}.vcf.gz
    rm results/${sample}.vcf
done

# Collapse step (idempotent)
NEED_REBUILD=false
if [[ ! -f results/collapsed.tsv ]]; then
    NEED_REBUILD=true
else
    for sample in "${SAMPLES[@]}"; do
        if [[ results/${sample}.vcf.gz -nt results/collapsed.tsv ]]; then
            NEED_REBUILD=true
            break
        fi
    done
fi

if $NEED_REBUILD; then
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > results/collapsed.tsv
    for sample in "${SAMPLES[@]}"; do
        bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" results/${sample}.vcf.gz >> results/collapsed.tsv
    done
fi