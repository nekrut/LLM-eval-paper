#!/usr/bin/env bash
set -euo pipefail

THREADS=4

# Exit early if final output already exists
if [[ -s results/collapsed.tsv ]]; then
    exit 0
fi

mkdir -p results

samples=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

for sample in "${samples[@]}"; do
    fq1="data/raw/${sample}_1.fq.gz"
    fq2="data/raw/${sample}_2.fq.gz"
    bam="results/${sample}.bam"

    # Align paired-end reads
    bwa mem -t "${THREADS}" data/ref/chrM.fa "$fq1" "$fq2" | \
        samtools view -@ "${THREADS}" -bS - > "${bam}"

    # Index BAM
    samtools index -@ "${THREADS}" "${bam}"

    # Variant calling (mpileup + call) producing compressed VCF
    bcftools mpileup -f data/ref/chrM.fa \
        --output - \
        --min-MQ 25 \
        --max-depth 1000 \
        -p "${THREADS}" \
        "${bam}" | \
        bcftools call -mv -Oz -p "${THREADS}" -o "results/${sample}.vcf.gz"

    # Index VCF
    tabix -p vcf "results/${sample}.vcf.gz"
done

# Build collapsed.tsv (tab‑separated, header included)
{
    echo -e "sample\tchrom\tpos\tref\talt\taf"
    for sample in "${samples[@]}"; do
        bcftools query -f '%CHROM\t%POS\t%REF\t%ALT[\t%AF]\n' "results/${sample}.vcf.gz" | \
            awk -v s="${sample}" '{print s"\t"$0}'
    done
} > results/collapsed.tsv