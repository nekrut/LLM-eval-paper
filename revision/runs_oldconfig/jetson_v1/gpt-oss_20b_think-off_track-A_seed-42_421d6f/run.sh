#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)

mkdir -p results

REF=data/ref/chrM.fa
if [ ! -f "${REF}.amb" ]; then
  samtools faidx "$REF"
  bwa index "$REF"
fi

for sample in "${SAMPLES[@]}"; do
  BAM=results/${sample}.bam
  BAI=results/${sample}.bam.bai
  VCF_GZ=results/${sample}.vcf.gz
  VCF_TBI=results/${sample}.vcf.gz.tbi

  if [ -f "$BAI" ] && [ -f "$VCF_TBI" ]; then
    continue
  fi

  RGLINE="@RG\\tID:${sample}\\tSM:${sample}\\tLB:${sample}\\tPL:ILLUMINA"
  bwa mem -t "$THREADS" -R "$RGLINE" data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz | \
    samtools sort -@ "$THREADS" -o "$BAM"

  samtools index -@ "$THREADS" "$BAM"

  tmp_vcf=results/${sample}.vcf
  lofreq call-parallel --pp-threads "$THREADS" -f "$REF" -b "$BAM" -o "$tmp_vcf"

  bgzip -c "$tmp_vcf" > "$VCF_GZ"
  tabix -p vcf "$VCF_GZ"
  rm -f "$tmp_vcf"
done

COLLAPSED=results/collapsed.tsv
REBUILD=false
if [ ! -f "$COLLAPSED" ]; then
  REBUILD=true
else
  for sample in "${SAMPLES[@]}"; do
    if [ "$(stat -c %Y results/${sample}.vcf.gz)" -gt "$(stat -c %Y "$COLLAPSED")" ]; then
      REBUILD=true
      break
    fi
  done
fi

if $REBUILD; then
  {
    printf "sample\tchrom\tpos\tref\talt\taf\n"
    for sample in "${SAMPLES[@]}"; do
      bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" results/${sample}.vcf.gz
    done
  } > "$COLLAPSED.tmp"
  mv "$COLLAPSED.tmp" "$COLLAPSED"
fi

exit 0