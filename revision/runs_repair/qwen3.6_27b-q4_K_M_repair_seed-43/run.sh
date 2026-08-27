#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

mkdir -p results

# Determine reference file path dynamically based on available files in data/ref/
REF_DIR="data/ref"
REF_FILE=""

if [[ -f "${REF_DIR}/chrM.fa" ]]; then
    REF_FILE="${REF_DIR}/chrM.fa"
elif [[ -d "${REF_DIR}/GRCh38_chrM" && -f "${REF_DIR}/GRCh38_chrM/rCRS.fa" ]]; then
    REF_FILE="${REF_DIR}/GRCh38_chrM/rCRS.fa"
else
    echo "Error: Could not find reference FASTA file in ${REF_DIR}" >&2
    exit 1
fi

# 1. Reference indexing — BWA
[[ -f "${REF_FILE}.bwt" ]] || bwa index "${REF_FILE}"

# 2. Reference indexing — samtools faidx
[[ -f "${REF_FILE}.fai" ]] || samtools faidx "${REF_FILE}"

for sample in "${SAMPLES[@]}"; do
    # 3. Per-sample alignment + sort
    [[ -f "results/${sample}.bam" ]] || { bwa mem -t ${THREADS} -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" "${REF_FILE}" data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz | samtools sort -@ ${THREADS} -o results/${sample}.bam - ; }

    # 4. BAM index
    [[ -f "results/${sample}.bam.bai" ]] || samtools index -@ ${THREADS} results/${sample}.bam

    # 5. Variant calling — LoFreq
    [[ -f "results/${sample}.vcf" || -f "results/${sample}.vcf.gz" ]] || lofreq call-parallel --pp-threads ${THREADS} -f "${REF_FILE}" -o results/${sample}.vcf results/${sample}.bam

    # 6. VCF compression + tabix index
    [[ -f "results/${sample}.vcf.gz.tbi" ]] || { bgzip -f results/${sample}.vcf && tabix -p vcf results/${sample}.vcf.gz ; }
done

# 7. Collapsed TSV (rebuild every run)
printf 'sample\tchrom\tpos\tref\talt\taf\n' > results/collapsed.tsv

for sample in "${SAMPLES[@]}"; do
    bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' results/${sample}.vcf.gz | awk -v s=${sample} 'BEGIN{OFS="\t"}{print s,$0}' >> results/collapsed.tsv
done