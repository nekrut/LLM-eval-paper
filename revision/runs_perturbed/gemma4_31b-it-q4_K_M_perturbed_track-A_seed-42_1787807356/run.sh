#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
REF="data/ref/GRCh38_chrM/rCRS.fa"

mkdir -p results

[[ -f "${REF}.bwt" ]] || bwa index "${REF}"
[[ -f "${REF}.fai" ]] || samtools faidx "${REF}"

for sample in "${SAMPLES[@]}"; do
    # Alignment and Sort
    if [[ ! -f "results/${sample}.bam" ]]; then
        bwa mem -t ${THREADS} -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" "${REF}" "data/raw/${sample}_1.fq.gz" "data/raw/${sample}_2.fq.gz" | samtools sort -@ ${THREADS} -o "results/${sample}.bam" -
    fi

    # BAM Index
    if [[ ! -f "results/${sample}.bam.bai" ]]; then
        samtools index -@ ${THREADS} "results/${sample}.bam"
    fi

    # Variant Calling
    if [[ ! -f "results/${sample}.vcf" && ! -f "results/${sample}.vcf.gz" ]]; then
        lofreq call-parallel --pp-threads ${THREADS} -f "${REF}" -o "results/${sample}.vcf" "results/${sample}.bam"
    fi

    # VCF Compression and Indexing
    if [[ ! -f "results/${sample}.vcf.gz.tbi" ]]; then
        bgzip -f "results/${sample}.vcf"
        tabix -p vcf "results/${sample}.vcf.gz"
    fi
done

printf 'sample\tchrom\tpos\tref\talt\taf\n' > results/collapsed.tsv
for sample in "${SAMPLES[@]}"; do
    bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "results/${sample}.vcf.gz" | awk -v s="${sample}" 'BEGIN{OFS="\t"}{print s,$0}' >> results/collapsed.tsv
done