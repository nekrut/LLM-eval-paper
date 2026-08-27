#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)

mkdir -p results

REF=data/ref/chrM.fa

# Reference indexing
if [ ! -f "${REF}.amb" ]; then
  bwa index "$REF"
fi
if [ ! -f "${REF}.fai" ]; then
  samtools faidx "$REF"
fi

for sample in "${SAMPLES[@]}"; do
  BAM=results/${sample}.bam
  BAI=${BAM}.bai
  VCF=results/${sample}.vcf
  VCF_GZ="${VCF}.gz"

  # Skip if final VCF index exists
  if [ -f "${VCF_GZ}.tbi" ]; then
    continue
  fi

  # Alignment and sorting
  if [ ! -f "$BAM" ]; then
    RG="@RG\\tID:${sample}\\tSM:${sample}\\tLB:${sample}\\tPL:ILLUMINA"
    bwa mem -t "$THREADS" -R "$RG" "$REF" "data/raw/${sample}_1.fq.gz" "data/raw/${sample}_2.fq.gz" | \
      samtools sort -@ "$THREADS" -o "$BAM"
  fi

  # BAM indexing
  if [ ! -f "$BAI" ] || [ "$BAI" -ot "$BAM" ]; then
    samtools index -@ "$THREADS" "$BAM"
  fi

  # Variant calling with lofreq
  if [ ! -f "${VCF_GZ}.tbi" ]; then
    lofreq call-parallel --pp-threads "$THREADS" -f "$REF" -b "$BAM" > "$VCF"
    bgzip -c "$VCF" > "${VCF}.gz"
    tabix -p vcf "${VCF}.gz"
    rm -f "$VCF"
  fi
done

# Collapsed table
COLLAPSED=results/collapsed.tsv
REBUILD=false
if [ ! -f "$COLLAPSED" ]; then REBUILD=true; fi
for sample in "${SAMPLES[@]}"; do
  VCF_TBI=results/${sample}.vcf.gz.tbi
  if [ "$VCF_TBI" -nt "$COLLAPSED" ]; then REBUILD=true; break; fi
done

if $REBUILD; then
  rm -f "$COLLAPSED"
  printf "sample\tchrom\tpos\tref\talt\taf\n" > "$COLLAPSED"
  for sample in "${SAMPLES[@]}"; do
    VCF_GZ=results/${sample}.vcf.gz
    bcftools query -f "${sample}\\t%CHROM\\t%POS\\t%REF\\t%ALT\\t%INFO/AF\n" "$VCF_GZ" >> "$COLLAPSED"
  done
fi