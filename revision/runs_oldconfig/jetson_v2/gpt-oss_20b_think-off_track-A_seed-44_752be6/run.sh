#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

mkdir -p results

# Reference indexing with BWA
if [[ ! -f data/ref/chrM.fa.bwt ]]; then
    bwa index data/ref/chrM.fa
fi

# Reference indexing with samtools faidx
if [[ ! -f data/ref/chrM.fa.fai ]]; then
    samtools faidx data/ref/chrM.fa
fi

for sample in "${SAMPLES[@]}"; do
    # Alignment and sorting to BAM
    if [[ ! -f results/${sample}.bam ]]; then
        bwa mem -t ${THREADS} -R "@RG\\tID:${sample}\\tSM:${sample}\\tLB:${sample}\\tPL:ILLUMINA" \
            data/ref/chrM.fa data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz |
            samtools sort -@ ${THREADS} -o results/${sample}.bam -
    fi

    # Index BAM
    if [[ ! -f results/${sample}.bam.bai ]]; then
        samtools index -@ ${THREADS} results/${sample}.bam
    fi

    # Variant calling with LoFreq
    if [[ ! -f results/${sample}.vcf && ! -f results/${sample}.vcf.gz ]]; then
        lofreq call-parallel --pp-threads ${THREADS} -f data/ref/chrM.fa \
            -o results/${sample}.vcf results/${sample}.bam
    fi

    # Compress VCF and create tabix index
    if [[ ! -f results/${sample}.vcf.gz.tbi ]]; then
        bcftools view -Oz -o results/${sample}.vcf.gz results/${sample}.vcf
        tabix -p vcf results/${sample}.vcf.gz
        rm -f results/${sample}.vcf
    fi
done

# Build collapsed TSV table
printf 'sample\tchrom\tpos\tref\talt\taf\n' > results/collapsed.tsv
for sample in "${SAMPLES[@]}"; do
    bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' \
        results/${sample}.vcf.gz | awk -v s=${sample} 'BEGIN{OFS="\t"}{print s,$0}' >> results/collapsed.tsv
done

exit 0