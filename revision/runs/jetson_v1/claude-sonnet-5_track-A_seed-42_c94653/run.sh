#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)
REF="data/ref/chrM.fa"

mkdir -p results

if [[ ! -f "${REF}.fai" ]]; then
  samtools faidx "$REF"
fi

if [[ ! -f "${REF}.bwt" ]]; then
  bwa index "$REF"
fi

for sample in "${SAMPLES[@]}"; do
  R1="data/raw/${sample}_1.fq.gz"
  R2="data/raw/${sample}_2.fq.gz"
  BAM="results/${sample}.bam"
  BAI="${BAM}.bai"

  if [[ ! -f "$BAM" || "$R1" -nt "$BAM" || "$R2" -nt "$BAM" ]]; then
    bwa mem -t "$THREADS" -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" "$REF" "$R1" "$R2" \
      | samtools sort -@ "$THREADS" -o "$BAM"
  fi

  if [[ ! -f "$BAI" || "$BAM" -nt "$BAI" ]]; then
    samtools index -@ "$THREADS" "$BAM"
  fi
done

for sample in "${SAMPLES[@]}"; do
  BAM="results/${sample}.bam"
  VCF="results/${sample}.vcf"
  VCFGZ="results/${sample}.vcf.gz"
  TBI="${VCFGZ}.tbi"

  if [[ ! -f "$TBI" || "$BAM" -nt "$TBI" ]]; then
    rm -f "$VCF" "$VCFGZ" "$TBI"
    lofreq call-parallel --pp-threads "$THREADS" -f "$REF" -o "$VCF" "$BAM"
    bgzip -f "$VCF"
    tabix -p vcf "$VCFGZ"
  fi
done

COLLAPSED="results/collapsed.tsv"
need_rebuild=0
if [[ ! -f "$COLLAPSED" ]]; then
  need_rebuild=1
else
  for sample in "${SAMPLES[@]}"; do
    VCFGZ="results/${sample}.vcf.gz"
    if [[ "$VCFGZ" -nt "$COLLAPSED" ]]; then
      need_rebuild=1
    fi
  done
fi

if [[ "$need_rebuild" -eq 1 ]]; then
  {
    printf 'sample\tchrom\tpos\tref\talt\taf\n'
    for sample in "${SAMPLES[@]}"; do
      bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "results/${sample}.vcf.gz"
    done
  } > "$COLLAPSED"
fi