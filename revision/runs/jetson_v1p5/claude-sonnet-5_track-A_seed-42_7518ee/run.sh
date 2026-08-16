#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
REF="data/ref/chrM.fa"

mkdir -p results

# 1. Reference indexing - BWA (skip if already indexed)
if [[ ! -f "${REF}.bwt" ]]; then
  bwa index "${REF}"
fi

# 2. Reference indexing - samtools faidx (skip if already indexed)
if [[ ! -f "${REF}.fai" ]]; then
  samtools faidx "${REF}"
fi

for sample in "${SAMPLES[@]}"; do
  BAM="results/${sample}.bam"
  BAI="results/${sample}.bam.bai"
  VCF_GZ="results/${sample}.vcf.gz"
  VCF_TBI="results/${sample}.vcf.gz.tbi"
  FQ1="data/raw/${sample}_1.fq.gz"
  FQ2="data/raw/${sample}_2.fq.gz"

  # 3. Alignment + sort (skip if BAM already present and non-empty)
  if [[ ! -s "${BAM}" ]]; then
    bwa mem -t "${THREADS}" \
      -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
      "${REF}" "${FQ1}" "${FQ2}" \
      | samtools sort -@ "${THREADS}" -o "${BAM}" -
  fi

  # 4. BAM index (skip if already present)
  if [[ ! -s "${BAI}" ]]; then
    samtools index -@ "${THREADS}" "${BAM}"
  fi

  # 5+6. Variant calling with LoFreq, then compress + index (skip if final outputs present)
  if [[ ! -s "${VCF_GZ}" || ! -s "${VCF_TBI}" ]]; then
    if [[ ! -s "results/${sample}.vcf" && ! -s "${VCF_GZ}" ]]; then
      lofreq call-parallel --pp-threads "${THREADS}" -f "${REF}" \
        -o "results/${sample}.vcf" "${BAM}"
    fi
    if [[ -s "results/${sample}.vcf" ]]; then
      bgzip -f "results/${sample}.vcf"
    fi
    tabix -f -p vcf "${VCF_GZ}"
  fi
done

# 7. Collapsed TSV (rebuilt fresh each run from existing per-sample VCFs)
printf 'sample\tchrom\tpos\tref\talt\taf\n' > results/collapsed.tsv
for sample in "${SAMPLES[@]}"; do
  VCF_GZ="results/${sample}.vcf.gz"
  bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "${VCF_GZ}" \
    | awk -v s="${sample}" 'BEGIN{OFS="\t"}{print s,$0}' >> results/collapsed.tsv
done