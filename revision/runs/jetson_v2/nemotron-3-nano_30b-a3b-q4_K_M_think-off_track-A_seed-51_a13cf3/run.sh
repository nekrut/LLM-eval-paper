#!/usr/bin/env bash
set -euo pipefail
THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
mkdir -p results

# Step 1: BWA index (guard)
[[ -f data/ref/chrM.fa.bwt ]] || bwa index data/ref/chrM.fa

# Step 2: samtools faidx (guard)
[[ -f data/ref/chrM.fa.fai ]] || samtools faidx data/ref/chrM.fa

# Step 3-6 per-sample loop
for sample in "${SAMPLES[@]}"; do
    # BAM generation and sorting guard
    [[ -f results/${sample}.bam ]] || {
        bwa mem -t ${THREADS} -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" data/ref/chrM.fa data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz | samtools sort -@ ${THREADS} -o results/${sample}.bam -
    }

    # BAM indexing guard
    [[ -f results/${sample}.bam.bai ]] || samtools index -@ ${THREADS} results/${sample}.bam

    # LoFreq variant calling guard (check both .vcf and .vcf.gz)
    if [[ ! -f results/${sample}.vcf && ! -f results/${sample}.vcf.gz ]]; then
        lofreq call-parallel --pp-threads ${THREADS} -f data/ref/chrM.fa -o results/${sample}.vcf results/${sample}.bam
    fi

    # BGZIP and tabix guard (check .tbi)
    if [[ ! -f results/${sample}.vcf.gz.tbi ]]; then
        bgzip -f results/${sample}.vcf && tabix -p vcf results/${sample}.vcf.gz
    fi
done

# Step 7: Rebuild collapsed.tsv (always overwrite header and append)
printf 'sample\tchrom\tpos\tref\talt\taf\n' > results/collapsed.tsv
for sample in "${SAMPLES[@]}"; do
    bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' results/${sample}.vcf.gz | awk -v s=${sample} 'BEGIN{OFS="\t"}{print s,$0}' >> results/collapsed.tsv
done