#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
mkdir -p results

# Reference indexing (BWA)
bwa index data/ref/chrM.fa

# Reference indexing (samtools faidx)
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

    # Append sample-specific data to collapsed TSV
    printf '%s\t%s\t%s\t%s\t%s\n' "${sample}" \
        "$(bcftools view -H results/${sample}.vcf.gz | head -n 1 | cut -f 1)" \
        "$(bcftools view -H results/${sample}.vcf.gz | head -n 1 | cut -f 2)" \
        "$(bcftools view -H results/${sample}.vcf.gz | head -n 1 | cut -f 3)" \
        "$(bcftools query -f '%INFO/AF\n' results/${sample}.vcf.gz | head -n 1)" >> results/collapsed.tsv
done

# Header for collapsed TSV (if not already present)
grep -q '^sample\tchrom\tpos\tref\talt\taf$' results/collapsed.tsv || \
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > results/collapsed.tsv