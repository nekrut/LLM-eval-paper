#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)

mkdir -p results

REF=data/ref/chrM.fa
if [ ! -f "${REF}.bwt" ]; then
  bwa index "$REF"
fi
if [ ! -f "${REF}.fai" ]; then
  samtools faidx "$REF"
fi

for sample in "${SAMPLES[@]}"; do
  R1=data/raw/${sample}_1.fq.gz
  R2=data/raw/${sample}_2.fq.gz
  BAM=results/${sample}.bam
  BAI=results/${sample}.bam.bai
  VCF_GZ=results/${sample}.vcf.gz
  TBI=results/${sample}.vcf.gz.tbi

  if [ -f "$BAM" ] && [ -f "$BAI" ] && [ -f "$VCF_GZ" ] && [ -f "$TBI" ]; then
    latest_input=0
    for f in "$R1" "$R2"; do
      ts=$(stat -c %Y "$f")
      if (( ts > latest_input )); then latest_input=$ts; fi
    done
    bam_ts=$(stat -c %Y "$BAM")
    bai_ts=$(stat -c %Y "$BAI")
    vcf_ts=$(stat -c %Y "$VCF_GZ")
    tbi_ts=$(stat -c %Y "$TBI")
    if (( bam_ts >= latest_input && bai_ts >= latest_input && vcf_ts >= latest_input && tbi_ts >= latest_input )); then
      continue
    fi
  fi

  bwa mem -t "$THREADS" -R "@RG\\tID:${sample}\\tSM:${sample}\\tLB:${sample}\\tPL:ILLUMINA" \
    "$REF" "$R1" "$R2" | samtools sort -@ "$THREADS" -o "$BAM"

  samtools index -@ "$THREADS" "$BAM"

  tmp_vcf=results/${sample}.vcf
  lofreq call-parallel --pp-threads "$THREADS" -f "$REF" -b "$BAM" -o "$tmp_vcf"

  bgzip -c "$tmp_vcf" > "$VCF_GZ"
  tabix -p vcf "$VCF_GZ"
  rm -f "$tmp_vcf"
done

COLLAPSED=results/collapsed.tsv
rebuild=false
if [ ! -f "$COLLAPSED" ]; then
  rebuild=true
else
  for sample in "${SAMPLES[@]}"; do
    VCF_GZ=results/${sample}.vcf.gz
    if (( $(stat -c %Y "$VCF_GZ") > $(stat -c %Y "$COLLAPSED") )); then
      rebuild=true
      break
    fi
  done
fi

if $rebuild; then
  printf "sample\tchrom\tpos\tref\talt\taf\n"
  for sample in "${SAMPLES[@]}"; do
    VCF_GZ=results/${sample}.vcf.gz
    bcftools query -f '{sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "$VCF_GZ"
  done > "$COLLAPSED"
fi

exit 0