#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

# Create output directory
mkdir -p results

# Reference indexing – BWA
[[ -f data/ref/chrM.fa.bwt ]] || bwa index data/ref/chrM.fa

# Reference indexing – samtools faidx
[[ -f data/ref/chrM.fa.fai ]] || samtools faidx data/ref/chrM.fa

for sample in "${SAMPLES[@]}"; do
    # Alignment and sort (one pipeline)
    [[ -f results/${sample}.bam ]] || {
        bwa mem -t ${THREADS} -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
            data/ref/chrM.fa data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz | \
        samtools sort -@ ${THREADS} -o results/${sample}.bam -
    }

    # BAM index
    [[ -f results/${sample}.bam.bai ]] || samtools index -@ ${THREADS} results/${sample}.bam

    # Variant calling – LoFreq
    [[ -f results/${sample}.vcf || -f results/${sample}.vcf.gz ]] || \
        lofreq call-parallel --pp-threads ${THREADS} -f data/ref/chrM.fa -o results/${sample}.vcf results/${sample}.bam

    # Compress and index VCF
    [[ -f results/${sample}.vcf.gz.tbi ]] || {
        if [[ -f results/${sample}.vcf ]]; then
            bcftools view -Oz -o results/${sample}.vcf.gz results/${sample}.vcf
        fi
        if [[ -f results/${sample}.vcf.gz ]]; then
            tabix -p vcf results/${sample}.vcf.gz
        fi
    }
done

# Collapsed TSV (rebuild every run)
printf 'sample\tchrom\tpos\tref\talt\taf\n' > results/collapsed.tsv
for sample in "${SAMPLES[@]}"; do
    bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' results/${sample}.vcf.gz | \
        awk -v s=${sample} 'BEGIN{OFS="\t"}{print s,$0}' >> results/collapsed.tsv
done