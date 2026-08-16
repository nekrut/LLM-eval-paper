#!/usr/bin/env bash
set -euo pipefail

# Globals
THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
REF="data/ref/chrM.fa"

# Prepare results directory
mkdir -p results

# ============================================================================
# Reference indexing (idempotent)
# ============================================================================

if [[ ! -f "${REF}.fai" ]]; then
  samtools faidx "${REF}"
fi

if [[ ! -f "${REF}.amb" ]]; then
  bwa index "${REF}"
fi

# ============================================================================
# Per-sample alignment, sorting, indexing
# ============================================================================

for sample in "${SAMPLES[@]}"; do
  bam="results/${sample}.bam"
  bai="results/${sample}.bam.bai"
  
  if [[ -f "${bam}" ]] && [[ -f "${bai}" ]]; then
    continue
  fi
  
  bwa mem -t "${THREADS}" -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
    "${REF}" \
    "data/raw/${sample}_1.fq.gz" \
    "data/raw/${sample}_2.fq.gz" | \
  samtools sort -@ "${THREADS}" -o "${bam}"
  
  samtools index -@ "${THREADS}" "${bam}"
done

# ============================================================================
# Variant calling and VCF compression
# ============================================================================

for sample in "${SAMPLES[@]}"; do
  bam="results/${sample}.bam"
  vcf_gz="results/${sample}.vcf.gz"
  vcf_tbi="results/${sample}.vcf.gz.tbi"
  vcf_tmp="results/${sample}.vcf"
  
  if [[ -f "${vcf_gz}" ]] && [[ -f "${vcf_tbi}" ]]; then
    continue
  fi
  
  lofreq call-parallel --pp-threads "${THREADS}" \
    -f "${REF}" \
    -o "${vcf_tmp}" \
    "${bam}"
  
  bgzip -f "${vcf_tmp}"
  
  tabix -p vcf "${vcf_gz}"
done

# ============================================================================
# Collapse to TSV
# ============================================================================

collapsed="results/collapsed.tsv"

rebuild=false
if [[ ! -f "${collapsed}" ]]; then
  rebuild=true
else
  for sample in "${SAMPLES[@]}"; do
    vcf_gz="results/${sample}.vcf.gz"
    if [[ "${vcf_gz}" -nt "${collapsed}" ]]; then
      rebuild=true
      break
    fi
  done
fi

if [[ "${rebuild}" == true ]]; then
  printf "sample\tchrom\tpos\tref\talt\taf\n" > "${collapsed}"
  
  for sample in "${SAMPLES[@]}"; do
    vcf_gz="results/${sample}.vcf.gz"
    bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "${vcf_gz}" >> "${collapsed}"
  done
fi

exit 0