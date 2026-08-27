#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
mkdir -p results

# Reference indexing
bwa index data/ref/chrM.fa
samtools faidx data/ref/chrM.fa

for sample in "${SAMPLES[@]}"; do
    # Alignment and sorting
    bwa mem -t ${THREADS} \
        -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
        data/ref/chrM.fa \
        data/raw/${sample}_1.fq.gz \
        data/raw/${sample}_2.fq.gz | \
    samtools sort -@ ${THREADS} -o results/${sample}.bam -

    # BAM indexing
    samtools index -@ ${THREADS} results/${sample}.bam

    # Variant calling with LoFreq
    lofreq call-parallel --pp-threads ${THREADS} \
        -f data/ref/chrM.fa \
        -o results/${sample}.vcf \
        results/${sample}.bam

    # VCF compression and tabix indexing
    bgzip -f results/${sample}.vcf
    tabix -p vcf results/${sample}.vcf.gz

    # Append sample info to collapsed TSV
    printf '%s\t%s\n' "${sample}" "$(bcftools view -h results/${sample}.vcf.gz | grep '^##INFO=<ID=AF')" >> results/collapsed.tsv
done

# Ensure collapsed.tsv has proper header and format
awk 'NR==1{print "sample\tchrom\tpos\tref\talt\taf"} NR>1' results/collapsed.tsv > tmp && mv tmp results/collapsed.tsv