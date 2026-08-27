#!/usr/bin/env bash
set -euo pipefail
THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
mkdir -p results

# 1. Reference indexing — BWA
if [ ! -f data/ref/chrM.fa.bwt ]; then
    bwa index data/ref/chrM.fa
fi

# 2. Reference indexing — samtools faidx
if [ ! -f data/ref/chrM.fa.fai ]; then
    samtools faidx data/ref/chrM.fa
fi

for sample in "${SAMPLES[@]}"; do
    # Check if all outputs for this sample already exist to ensure idempotency
    if [ -f "results/${sample}.bam" ] && \
       [ -f "results/${sample}.bam.bai" ] && \
       [ -f "results/${sample}.vcf.gz" ] && \
       [ -f "results/${sample}.vcf.gz.tbi" ]; then
        continue
    fi

    # 3. Per-sample alignment + sort
    bwa mem -t ${THREADS} -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" data/ref/chrM.fa "data/raw/${sample}_1.fq.gz" "data/raw/${sample}_2.fq.gz" | samtools sort -@ ${THREADS} -o "results/${sample}.bam" -

    # 4. BAM index
    samtools index -@ ${THREADS} "results/${sample}.bam"

    # 5. Variant calling — LoFreq
    lofreq call-parallel --pp-threads ${THREADS} -f data/ref/chrM.fa -o "results/${sample}.vcf" "results/${sample}.bam"

    # 6. VCF compression + tabix index
    bgzip -f "results/${sample}.vcf"
    tabix -p vcf "results/${sample}.vcf.gz"
done

# 7. Collapsed TSV
printf 'sample\tchrom\tpos\tref\talt\taf\n' > results/collapsed.tsv

for sample in "${SAMPLES[@]}"; do
    bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "results/${sample}.vcf.gz" | awk -v s="${sample}" 'BEGIN{OFS="\t"}{print s,$0}' >> results/collapsed.tsv
done