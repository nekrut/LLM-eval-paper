#!/usr/bin/env bash
set -euo pipefail
THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
mkdir -p results

# Reference indexing (Steps 1 & 2)
if [ ! -f data/ref/chrM.fa.bwt ]; then
    bwa index data/ref/chrM.fa
    samtools faidx data/ref/chrM.fa
fi

# Per-sample processing (Steps 3-6)
for sample in "${SAMPLES[@]}"; do
    # Step 3: Alignment + Sort
    if [ ! -f results/${sample}.bam ]; then
        bwa mem -t $THREADS -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" data/ref/chrM.fa data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz | samtools sort -@ $THREADS -o results/${sample}.bam -
    fi

    # Step 4: BAM index
    if [ ! -f results/${sample}.bam.bai ]; then
        samtools index -@ $THREADS results/${sample}.bam
    fi

    # Step 5: Variant calling
    if [ ! -f results/${sample}.vcf ]; then
        lofreq call-parallel --pp-threads $THREADS -f data/ref/chrM.fa -o results/${sample}.vcf results/${sample}.bam
    fi

    # Step 6: VCF compression + tabix
    if [ ! -f results/${sample}.vcf.gz ]; then
        bgzip -f results/${sample}.vcf
        tabix -p vcf results/${sample}.vcf.gz
    fi
done

# Collapsed TSV (Step 7)
if [ ! -s results/collapsed.tsv ]; then
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > results/collapsed.tsv
    for sample in "${SAMPLES[@]}"; do
        bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' results/${sample}.vcf.gz | awk -v s="${sample}" 'BEGIN{OFS="\t"}{print s,$0}' >> results/collapsed.tsv
    done
fi