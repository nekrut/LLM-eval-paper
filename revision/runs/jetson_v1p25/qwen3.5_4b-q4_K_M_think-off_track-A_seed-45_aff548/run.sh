#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
REF="data/ref/chrM.fa"
RAW_DIR="data/raw"
RESULTS_DIR="results"

mkdir -p "$RESULTS_DIR"

# 2. Reference indexing (once)
if [ ! -f "${REF}.faidx" ] || [ ! -f "${REF}.amb" ]; then
    samtools faidx "$REF" > /dev/null
    bwa index "$REF" > /dev/null
fi

for sample in "${SAMPLES[@]}"; do
  # Check idempotency for per-sample outputs (vcf.gz.tbi is the anchor)
  if [ -f "${RESULTS_DIR}/${sample}.vcf.gz.tbi" ]; then
    continue
  fi

  R1="${RAW_DIR}/${sample}_1.fq.gz"
  R2="${RAW_DIR}/${sample}_2.fq.gz"

  # Ensure inputs exist (idempotent check implicitly handled by set -e)
  if [ ! -f "$R1" ] || [ ! -f "$R2" ]; then
    echo "Error: Missing input files for sample $sample" >&2
    exit 1
  fi

  # Step 3. Alignment with bwa mem (using literal backslash-t in RG)
  bwa mem -t ${THREADS} \
    -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
    "$REF" "$R1" "$R2" | samtools sort -@ ${THREADS} -o "${RESULTS_DIR}/${sample}.bam"

  # Step 5. BAM indexing
  samtools index -@ ${THREADS} "${RESULTS_DIR}/${sample}.bam" > /dev/null

  # Step 6. Variant calling with lofreq call-parallel
  lofreq call-parallel --pp-threads ${THREADS} \
    -f "$REF" \
    -o "${RESULTS_DIR}/${sample}.vcf" \
    "${RESULTS_DIR}/${sample}.bam" > /dev/null

  # Step 7. VCF compression and indexing (remove uncompressed intermediate)
  bgzip -c "${RESULTS_DIR}/${sample}.vcf" > "${RESULTS_DIR}/${sample}.vcf.gz" && rm -f "${RESULTS_DIR}/${sample}.vcf"
  tabix -p vcf "${RESULTS_DIR}/${sample}.vcf.gz"

done

# Step 8. Collapse step -> results/collapsed.tsv
if [ ! -f "${RESULTS_DIR}/collapsed.tsv" ]; then
  {
    echo "sample	chrom	pos	ref	alt	af"
    
    for sample in "${SAMPLES[@]}"; do
      bcftools query \
        -f '{CHROM}\t{POS}\t{REF}\t{ALT}\t{INFO/AF}' \
        "${RESULTS_DIR}/${sample}.vcf.gz" | while IFS=$'\t' read -r chrom pos ref alt af; do
          echo "$sample	$chrom	$pos	$ref	$alt	$af"
      done
    done
  } > "${RESULTS_DIR}/collapsed.tsv"
fi