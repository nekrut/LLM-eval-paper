#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

mkdir -p results

# Reference indexing — BWA (idempotent)
if [ ! -f data/ref/chrM.fa.bwt ]; then
    bwa index data/ref/chrM.fa
fi

# Reference indexing — samtools faidx (idempotent)
if [ ! -f data/ref/chrM.fa.fai ]; then
    samtools faidx data/ref/chrM.fa
fi

for sample in "${SAMPLES[@]}"; do
    # Per-sample alignment + sort (idempotent check on BAM existence and freshness)
    if [ ! -f results/${sample}.bam ] || \
       { [ data/raw/${sample}_1.fq.gz -nt results/${sample}.bam ] 2>/dev/null || true; }; then
        bwa mem -t ${THREADS} \
            -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
            data/ref/chrM.fa \
            data/raw/${sample}_1.fq.gz \
            data/raw/${sample}_2.fq.gz | \
        samtools sort -@ ${THREADS} -o results/${sample}.bam -
    fi

    # BAM index (idempotent)
    if [ ! -f results/${sample}.bam.bai ]; then
        samtools index -@ ${THREADS} results/${sample}.bam
    fi

    # Variant calling — LoFreq (idempotent check on VCF.gz existence and freshness)
    if [ ! -f results/${sample}.vcf.gz ] || \
       { [ results/${sample}.bam -nt results/${sample}.vcf.gz ] 2>/dev/null || true; }; then
        lofreq call-parallel --pp-threads ${THREADS} \
            -f data/ref/chrM.fa \
            -o results/${sample}.vcf \
            results/${sample}.bam
    fi

    # VCF compression + tabix index (idempotent)
    if [ ! -f results/${sample}.vcf.gz.tbi ]; then
        bgzip -f results/${sample}.vcf
        tabix -p vcf results/${sample}.vcf.gz
    fi
done

# Collapsed TSV generation (recreate from all sample VCFs)
printf 'sample\tchrom\tpos\tref\talt\taf\n' > results/collapsed.tsv
for sample in "${SAMPLES[@]}"; do
    bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' \
        results/${sample}.vcf.gz | \
    awk -v s=${sample} 'BEGIN{OFS="\t"}{print s,$0}' >> results/collapsed.tsv
done