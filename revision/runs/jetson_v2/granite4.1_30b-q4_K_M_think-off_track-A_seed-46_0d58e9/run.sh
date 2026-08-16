#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
mkdir -p results

# 1. BWA reference indexing (idempotent)
[[ -f data/ref/chrM.fa.bwt ]] || bwa index data/ref/chrM.fa

# 2. samtools faidx (idempotent)
[[ -f data/ref/chrM.fa.fai ]] || samtools faidx data/ref/chrM.fa

for sample in "${SAMPLES[@]}"; do
    # 3. Alignment + sorting (idempotent on BAM output)
    if [[ -f results/${sample}.bam ]]; then
        continue
    fi
    {
        bwa mem -t ${THREADS} \
            -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
            data/ref/chrM.fa \
            data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz |
        samtools sort -@ ${THREADS} -o results/${sample}.bam -
    }

    # 4. Index BAM (idempotent on BAI output)
    [[ -f results/${sample}.bam.bai ]] || samtools index -@ ${THREADS} results/${sample}.bam

    # 5. LoFreq variant calling (idempotent on VCF presence)
    if [[ -f results/${sample}.vcf.gz ]] || [[ -f results/${sample}.vcf ]]; then
        :
    else
        lofreq call-parallel --pp-threads ${THREADS} \
            -f data/ref/chrM.fa \
            -o results/${sample}.vcf \
            results/${sample}.bam
    fi

    # 6. Compress VCF and index (idempotent on TBI output)
    if [[ -f results/${sample}.vcf.gz.tbi ]]; then
        :
    else
        bgzip -f results/${sample}.vcf
        tabix -p vcf results/${sample}.vcf.gz
    fi
done

# 7. Rebuild collapsed TSV from all VCFs (always run)
printf 'sample\tchrom\tpos\tref\talt\taf\n' > results/collapsed.tsv
for sample in "${SAMPLES[@]}"; do
    bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' \
        results/${sample}.vcf.gz |
    awk -v s=${sample} 'BEGIN{OFS="\t"}{print s,$0}' >> results/collapsed.tsv
done