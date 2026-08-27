#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
mkdir -p results

# 1. BWA reference indexing (idempotent)
[[ -f data/ref/chrM.fa.bwt ]] || bwa index data/ref/rCRS.fa

# 2. samtools faidx (idempotent)
[[ -f data/ref/chrM.fa.fai ]] || samtools faidx data/ref/rCRS.fa

for sample in "${SAMPLES[@]}"; do
    # 3. Alignment + sort (guard on final BAM)
    if [[ ! -f results/${sample}.bam ]]; then
        bwa mem -t ${THREADS} \
            -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
            data/ref/rCRS.fa \
            data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz |
        samtools sort -@ ${THREADS} -o results/${sample}.bam -
    fi

    # 4. Index BAM (guard on BAI)
    if [[ ! -f results/${sample}.bam.bai ]]; then
        samtools index -@ ${THREADS} results/${sample}.bam
    fi

    # 5. LoFreq variant calling (guard on VCF presence)
    if [[ ! -f results/${sample}.vcf && ! -f results/${sample}.vcf.gz ]]; then
        lofreq call-parallel --pp-threads ${THREADS} \
            -f data/ref/rCRS.fa \
            -o results/${sample}.vcf \
            results/${sample}.bam
    fi

    # 6. Compress VCF + tabix index (guard on TBI)
    if [[ ! -f results/${sample}.vcf.gz.tbi ]]; then
        bgzip -f results/${sample}.vcf
        tabix -p vcf results/${sample}.vcf.gz
    fi
done

# 7. Collapsed TSV – always rebuild (header + per-sample rows)
printf 'sample\tchrom\tpos\tref\talt\taf\n' > results/collapsed.tsv
for sample in "${SAMPLES[@]}"; do
    bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' \
        results/${sample}.vcf.gz |
    awk -v s=${sample} 'BEGIN{OFS="\t"}{print s,$0}' >> results/collapsed.tsv
done