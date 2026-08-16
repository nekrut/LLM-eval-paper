#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

mkdir -p results

# 2. Reference indexing (once)
if [ ! -f data/ref/chrM.fa.fai ]; then
    samtools faidx data/ref/chrM.fa
fi
if [ ! -f data/ref/chrM.fa.bwt ]; then
    bwa index data/ref/chrM.fa
fi

# Per-sample processing
for SAMPLE in "${SAMPLES[@]}"; do
    # 3. Alignment
    if [ ! -f results/${SAMPLE}.bam ]; then
        bwa mem -t $THREADS -R "@RG\tID:${SAMPLE}\tSM:${SAMPLE}\tLB:${SAMPLE}\tPL:ILLUMINA" data/ref/chrM.fa data/raw/${SAMPLE}_1.fq.gz data/raw/${SAMPLE}_2.fq.gz | samtools sort -@ $THREADS -o results/${SAMPLE}.bam
    fi

    # 5. BAM indexing
    if [ ! -f results/${SAMPLE}.bam.bai ]; then
        samtools index -@ $THREADS results/${SAMPLE}.bam
    fi

    # 6. Variant calling
    if [ ! -f results/${SAMPLE}.vcf.gz ]; then
        lofreq call-parallel --pp-threads $THREADS -f data/ref/chrM.fa results/${SAMPLE}.bam -o results/${SAMPLE}.vcf
        # 7. Compression and indexing
        bgzip -c results/${SAMPLE}.vcf > results/${SAMPLE}.vcf.gz
        tabix -p vcf results/${SAMPLE}.vcf.gz
        rm results/${SAMPLE}.vcf
    fi
done

# 8. Collapse
# Rebuild only if any input VCF is newer than the TSV
NEED_REBUILD=false
if [ ! -f results/collapsed.tsv ]; then
    NEED_REBUILD=true
else
    for SAMPLE in "${SAMPLES[@]}"; do
        if [ results/${SAMPLE}.vcf.gz -nt results/collapsed.tsv ]; then
            NEED_REBUILD=true
            break
        fi
    done
fi

if [ "$NEED_REBUILD" = true ]; then
    echo -e "sample\tchrom\tpos\tref\talt\taf" > results/collapsed.tsv
    for SAMPLE in "${SAMPLES[@]}"; do
        bcftools query -f '{sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' results/${SAMPLE}.vcf.gz >> results/collapsed.tsv
    done
fi