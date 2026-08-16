#!/usr/bin/env bash
set -euo pipefail

# Ensure output directory exists
mkdir -p results

# Reference genome (already decompressed)
REF="data/ref/chrM.fa"
BAM_DIR="results"
VCF_DIR="results"

# Index reference if not present
if [[ ! -f "${REF}.fai" ]]; then
  samtools faidx "${REF}"
fi
if [[ ! -f "${REF}.bwt" ]]; then
  bwa index "${REF}"
fi

THREADS=4

samples=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

for sample in "${samples[@]}"; do
  R1="data/raw/${sample}_1.fq.gz"
  R2="data/raw/${sample}_2.fq.gz"
  OUT_BAM="${BAM_DIR}/${sample}.bam"
  OUT_VCF_GZ="${VCF_DIR}/${sample}.vcf.gz"

  # Skip if final VCF already exists (idempotence)
  if [[ -f "${OUT_VCF_GZ}" && -f "${OUT_VCF_GZ}.tbi" ]]; then
    continue
  fi

  # Align with BWA MEM
  bwa mem -t "${THREADS}" "${REF}" "${R1}" "${R2}" \
    | samtools view -bS - > "${OUT_BAM}.unsorted.bam"

  # Sort and index BAM
  samtools sort -@ "${THREADS}" -o "${OUT_BAM}" "${OUT_BAM}.unsorted.bam"
  rm "${OUT_BAM}.unsorted.bam"
  samtools index "${OUT_BAM}"

  # Call variants with LoFreq Star
  lofreq star --call-option vcf \
    -f "${REF}" \
    -r chrM \
    -b "${OUT_BAM}" \
    -o "${OUT_VCF_GZ}"

  # Tabix index VCF
  tabix -p vcf "${OUT_VCF_GZ}"
done

# Collapse variants into a single TSV with header
COLLAPSED="results/collapsed.tsv"
if [[ ! -f "${COLLAPSED}" ]]; then
  {
    echo "sample\tchrom\tpos\tref\talt\taf"
    for sample in "${samples[@]}"; do
      VCF="${BAM_DIR}/${sample}.vcf.gz"
      zcat "${VCF}" \
        | grep -v '^#' \
        | awk -F'\t' '{
          if ($1 == "chrM") {
            printf("%s\t%s\t%s\t%s\t%s\t%.6f\n", "'${sample}'", $1, $2, $3, $4, $0);
          }
        }'
    done
  } > "${COLLAPSED}"
fi