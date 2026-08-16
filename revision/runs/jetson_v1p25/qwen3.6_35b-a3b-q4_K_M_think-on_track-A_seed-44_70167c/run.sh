#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)

mkdir -p results

# Reference indexing (once)
if [[ ! -f data/ref/chrM.fa.fai || ! -f data/ref/chrM.fa.amb ]]; then
    samtools faidx data/ref/chrM.fa
    bwa index data/ref/chrM.fa
fi

# Per-sample processing
for sample in "${SAMPLES[@]}"; do
    if [[ -f "results/${sample}.vcf.gz.tbi" ]]; then
        continue
    fi

    # Alignment & sorting
    bwa mem -t ${THREADS} \
        -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
        data/ref/chrM.fa \
        "data/raw/${sample}_1.fq.gz" \
        "data/raw/${sample}_2.fq.gz" | \
        samtools sort -@ ${THREADS} -o "results/${sample}.bam" -

    # BAM indexing
    samtools index -@ ${THREADS} "results/${sample}.bam"

    # Variant calling
    lofreq call-parallel --pp-threads ${THREADS} \
        -f data/ref/chrM.fa \
        -o "results/${sample}.vcf" \
        "results/${sample}.bam"

    # VCF compression & indexing
    bgzip -c "results/${sample}.vcf" > "results/${sample}.vcf.gz"
    tabix -p vcf "results/${sample}.vcf.gz"
    rm "results/${sample}.vcf"
done

# Collapse step
if [[ ! -f results/collapsed.tsv ]]; then
    {
        printf "sample\tchrom\tpos\tref\talt\taf\n"
        for sample in "${SAMPLES[@]}"; do
            bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "results/${sample}.vcf.gz"
        done
    } > results/collapsed.tsv
fi