#!/usr/bin/env bash
set -euo pipefail

RESULTS_DIR="results"
mkdir -p "$RESULTS_DIR"

# List of samples (paired)
samples=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

# Ensure collapsed.tsv header exists
if [ ! -s "${RESULTS_DIR}/collapsed.tsv" ]; then
    echo "sample\tchrom\tpos\tref\talt\taf" > "${RESULTS_DIR}/collapsed.tsv"
fi

for sample in "${samples[@]}"; do
    # Skip if BAM already exists (idempotent)
    if [ -f "${RESULTS_DIR}/${sample}.bam" ]; then
        continue
    fi

    # Uncompress FASTQ to temporary .fastq files under results/
    samtools fastq data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz \
        "${RESULTS_DIR}/${sample}_1.fastq" "${RESULTS_DIR}/${sample}_2.fastq"

    # BWA alignment
    bwa mem data/ref/chrM.fa "${RESULTS_DIR}/${sample}_1.fastq" "${RESULTS_DIR}/${sample}_2.fastq" \
        > "${RESULTS_DIR}/${sample}.bam"

    samtools index "${RESULTS_DIR}/${sample}.bam"

    # LOFREQ variant calling
    lofreq -o "${RESULTS_DIR}/${sample}.vcf.gz" "${RESULTS_DIR}/${sample}.bam"

    tabix "${RESULTS_DIR}/${sample}.vcf.gz"

    # Append variant lines to collapsed.tsv (skip header)
    bcftools view -T 0 "${RESULTS_DIR}/${sample}.vcf.gz" | awk 'NR>1 {print $1 "\t"$2 "\t"$3 "\t"$4 "\t"$5 "\t"$6}' \
        >> "${RESULTS_DIR}/collapsed.tsv"
done

exit 0