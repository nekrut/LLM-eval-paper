#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
mkdir -p results

# Reference indexing (idempotent)
bwa index data/ref/chrM.fa || true
samtools faidx data/ref/chrM.fa || true

for sample in "${SAMPLES[@]}"; do
    # Skip if final VCF already exists (idempotence)
    if [[ -f results/${sample}.vcf.gz ]]; then
        continue
    fi

    # 3. Alignment + sort BAM
    bwa mem -t ${THREADS} \
        -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
        data/ref/chrM.fa \
        data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz |
    samtools sort -@ ${THREADS} -o results/${sample}.bam -

    # 4. Index BAM
    samtools index -@ ${THREADS} results/${sample}.bam

    # 5. Variant calling with LoFreq
    lofreq call-parallel --pp-threads ${THREADS} \
        -f data/ref/chrM.fa \
        -o results/${sample}.vcf \
        results/${sample}.bam

    # 6. Compress VCF and index
    bgzip -f results/${sample}.vcf
    tabix -p vcf results/${sample}.vcf.gz

    # 7. Append to collapsed TSV (create header if file does not exist)
    if [[ ! -f results/collapsed.tsv ]]; then
        printf 'sample\tchrom\tpos\tref\talt\taf\n' > results/collapsed.tsv
    fi
    bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' results/${sample}.vcf.gz |
    awk -v s=${sample} 'BEGIN{OFS="\t"}{print s,$0}' >> results/collapsed.tsv
done