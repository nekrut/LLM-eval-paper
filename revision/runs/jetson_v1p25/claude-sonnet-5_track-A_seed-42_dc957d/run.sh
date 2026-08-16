#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)
REF="data/ref/chrM.fa"

mkdir -p results

# --- Reference indexing (once) ---
if [[ ! -f "${REF}.fai" ]]; then
  samtools faidx "$REF"
fi

need_bwa_index=false
for ext in amb ann bwt pac sa; do
  if [[ ! -f "${REF}.${ext}" ]]; then
    need_bwa_index=true
  fi
done
if [[ "$need_bwa_index" == true ]]; then
  bwa index "$REF"
fi

# --- Per-sample processing ---
for sample in "${SAMPLES[@]}"; do
  R1="data/raw/${sample}_1.fq.gz"
  R2="data/raw/${sample}_2.fq.gz"
  BAM="results/${sample}.bam"
  BAI="results/${sample}.bam.bai"
  VCF="results/${sample}.vcf"
  VCFGZ="results/${sample}.vcf.gz"
  TBI="results/${sample}.vcf.gz.tbi"

  if [[ ! -f "$BAM" || "$R1" -nt "$BAM" || "$R2" -nt "$BAM" ]]; then
    bwa mem -t "$THREADS" \
      -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
      "$REF" "$R1" "$R2" \
      | samtools sort -@ "$THREADS" -o "$BAM" -
  fi

  if [[ ! -f "$BAI" || "$BAM" -nt "$BAI" ]]; then
    samtools index -@ "$THREADS" "$BAM"
  fi

  if [[ ! -f "$TBI" || "$BAM" -nt "$TBI" ]]; then
    if [[ ! -f "$VCFGZ" || "$BAM" -nt "$VCFGZ" ]]; then
      lofreq call-parallel --pp-threads "$THREADS" -f "$REF" -o "$VCF" "$BAM"
      bgzip -f "$VCF"
    fi
    tabix -p vcf -f "$VCFGZ"
  fi
done

# --- Collapse step ---
COLLAPSED="results/collapsed.tsv"
need_collapse=false
if [[ ! -f "$COLLAPSED" ]]; then
  need_collapse=true
else
  for sample in "${SAMPLES[@]}"; do
    if [[ "results/${sample}.vcf.gz" -nt "$COLLAPSED" ]]; then
      need_collapse=true
    fi
  done
fi

if [[ "$need_collapse" == true ]]; then
  {
    printf 'sample\tchrom\tpos\tref\talt\taf\n'
    for sample in "${SAMPLES[@]}"; do
      bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "results/${sample}.vcf.gz"
    done
  } > "$COLLAPSED"
fi