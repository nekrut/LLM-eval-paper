#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)

mkdir -p results

REF=data/ref/chrM.fa

if [[ ! -f ${REF}.bwt ]]; then
  samtools faidx "$REF"
  bwa index "$REF"
fi

for sample in "${SAMPLES[@]}"; do
  fq1="data/raw/${sample}_1.fq.gz"
  fq2="data/raw/${sample}_2.fq.gz"
  bam="results/${sample}.bam"
  bai="results/${sample}.bam.bai"
  vcf="results/${sample}.vcf"
  vcfgz="results/${sample}.vcf.gz"

  if [[ ! -f "$bam" ]]; then
    bwa mem -t "$THREADS" -R "@RG\\tID:${sample}\\tSM:${sample}\\tLB:${sample}\\tPL:ILLUMINA" \
      "$REF" "$fq1" "$fq2" | samtools sort -@ "$THREADS" -o "$bam"
  fi

  if [[ ! -f "$bai" ]]; then
    samtools index -@ "$THREADS" "$bam"
  fi

  if [[ ! -f "$vcf" ]]; then
    lofreq call-parallel --pp-threads "$THREADS" -f "$REF" -o "$vcf" "$bam"
  fi

  if [[ ! -f "$vcfgz" ]]; then
    bgzip -c "$vcf" > "$vcfgz"
    tabix -p vcf "$vcfgz"
    rm -f "$vcf"
  fi
done

collapsed="results/collapsed.tsv"

if [[ ! -f "$collapsed" ]]; then
  {
    printf "sample\tchrom\tpos\tref\talt\taf\n"
    for sample in "${SAMPLES[@]}"; do
      bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "results/${sample}.vcf.gz"
    done
  } > "$collapsed"
fi

exit 0