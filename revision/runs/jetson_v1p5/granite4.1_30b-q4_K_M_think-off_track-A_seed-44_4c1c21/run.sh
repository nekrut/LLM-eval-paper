#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
mkdir -p results

# Reference indexing (idempotent)
if [[ ! -f data/ref/chrM.fa.bwt ]]; then
    bwa index data/ref/chrM.fa
fi
if [[ ! -f data/ref/chrM.fa.fai ]]; then
    samtools faidx data/ref/chrM.fa
fi

for sample in "${SAMPLES[@]}"; do
    # Skip if final VCF already exists (idempotence)
    if [[ -f results/${sample}.vcf.gz && -f results/${sample}.vcf.gz.tbi ]]; then
        continue
    fi

    # 3. Alignment + sort BAM
    bwa mem -t "${THREADS}" \
        -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
        data/ref/chrM.fa \
        data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz |
    samtools sort -@ "${THREADS}" -o results/${sample}.bam -

    # 4. Index BAM
    if [[ ! -f results/${sample}.bam.bai ]]; then
        samtools index -@ "${THREADS}" results/${sample}.bam
    fi

    # 5. Variant calling with LoFreq (produces uncompressed VCF)
    lofreq call-parallel --pp-threads "${THREADS}" \
        -f data/ref/chrM.fa \
        -o results/${sample}.vcf \
        results/${sample}.bam

    # 6. Compress VCF and index
    if [[ ! -f results/${sample}.vcf.gz ]]; then
        bgzip -f results/${sample}.vcf
    fi
    if [[ ! -f results/${sample}.vcf.gz.tbi ]]; then
        tabix -p vcf results/${sample}.vcf.gz
    fi

done

# 7. Collapsed TSV (re‑create each run for consistency)
> results/collapsed.tsv
printf 'sample\tchrom\tpos\tref\talt\taf\n' > results/collapsed.tsv
for sample in "${SAMPLES[@]}"; do
    bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "results/${sample}.vcf.gz" |
        awk -v s="${sample}" 'BEGIN{OFS="\t"}{print s,$0}' >> results/collapsed.tsv
done