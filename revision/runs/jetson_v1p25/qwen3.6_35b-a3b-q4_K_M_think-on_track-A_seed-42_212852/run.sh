#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES="M117-bl M117-ch M117C1-bl M117C1-ch"

mkdir -p results

# 2. Reference indexing (once)
if [ ! -f data/ref/chrM.fa.fai ]; then
    samtools faidx data/ref/chrM.fa
fi
if [ ! -f data/ref/chrM.fa.amb ]; then
    bwa index data/ref/chrM.fa
fi

# 3-7. Per-sample processing
for sample in ${SAMPLES}; do
    # 3 & 4. Alignment and sorted BAM
    if [ ! -f results/${sample}.bam ]; then
        bwa mem -t ${THREADS} -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" data/ref/chrM.fa data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz | \
            samtools sort -@ ${THREADS} -o results/${sample}.bam
    fi

    # 5. BAM indexing
    if [ ! -f results/${sample}.bam.bai ]; then
        samtools index -@ ${THREADS} results/${sample}.bam
    fi

    # 6. Variant calling
    if [ ! -f results/${sample}.vcf.gz.tbi ]; then
        lofreq call-parallel --pp-threads 4 -f data/ref/chrM.fa -o results/${sample}.vcf results/${sample}.bam
    fi

    # 7. VCF compression and indexing
    if [ ! -f results/${sample}.vcf.gz.tbi ]; then
        bgzip -c results/${sample}.vcf > results/${sample}.vcf.gz
        tabix -p vcf results/${sample}.vcf.gz
        rm results/${sample}.vcf
    fi
done

# 8. Collapse step
COLLAPSED="results/collapsed.tsv"
REBUILD_COLLAPSED=false

if [ ! -f "$COLLAPSED" ]; then
    REBUILD_COLLAPSED=true
else
    for sample in ${SAMPLES}; do
        if [ results/${sample}.vcf.gz.tbi -nt "$COLLAPSED" ]; then
            REBUILD_COLLAPSED=true
            break
        fi
    done
fi

if [ "$REBUILD_COLLAPSED" = true ]; then
    printf "sample\tchrom\tpos\tref\talt\taf\n" > "$COLLAPSED"
    for sample in ${SAMPLES}; do
        bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" results/${sample}.vcf.gz >> "$COLLAPSED"
    done
fi