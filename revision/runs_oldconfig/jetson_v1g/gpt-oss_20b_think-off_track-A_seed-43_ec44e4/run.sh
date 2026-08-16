#!/usr/bin/env bash
set -euo pipefail

THREADS=4
samples=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

mkdir -p results

ref="data/ref/chrM.fa"
if [ ! -f "${ref}.fai" ]; then
  samtools faidx "$ref"
fi
if [ ! -f "${ref}.amb" ]; then
  bwa index "$ref"
fi

for sample in "${samples[@]}"; do
  fq1="data/raw/${sample}_1.fq.gz"
  fq2="data/raw/${sample}_2.fq.gz"
  bam="results/${sample}.bam"
  bai="results/${sample}.bam.bai"
  vcf="results/${sample}.vcf"
  vcfgz="results/${sample}.vcf.gz"
  tbi="results/${sample}.vcf.gz.tbi"

  if [ ! -f "$bam" ] || [ "$fq1" -nt "$bam" ] || [ "$fq2" -nt "$bam" ]; then
    bwa mem -t "$THREADS" -R "@RG\\tID:${sample}\\tSM:${sample}\\tLB:${sample}\\tPL:ILLUMINA" \
      "$fq1" "$fq2" | samtools sort -@ "$THREADS" -o "$bam"
  fi

  if [ ! -f "$bai" ] || [ "$bam" -nt "$bai" ]; then
    samtools index -@ "$THREADS" "$bam"
  fi

  if [ ! -f "$vcf" ] || [ "$bam" -nt "$vcf" ] || [ "$ref" -nt "$vcf" ]; then
    lofreq call-parallel --pp-threads "$THREADS" --verbose \
      --ref "$ref" --out "$vcf" \
      --sig --bonf \
      "$bam"
  fi

  if [ ! -f "$vcfgz" ] || [ "$vcf" -nt "$vcfgz" ]; then
    bgzip -c "$vcf" > "$vcfgz"
    rm "$vcf"
  fi
  if [ ! -f "$tbi" ] || [ "$vcfgz" -nt "$tbi" ]; then
    tabix -p vcf "$vcfgz"
  fi
done

collapsed="results/collapsed.tsv"
rebuild=false
for sample in "${samples[@]}"; do
  vcfgz="results/${sample}.vcf.gz"
  if [ ! -f "$collapsed" ] || [ "$vcfgz" -nt "$collapsed" ]; then
    rebuild=true
    break
  fi
done

if $rebuild; then
  tmp=$(mktemp)
  printf "sample\tchrom\tpos\tref\talt\taf\n" > "$tmp"
  for sample in "${samples[@]}"; do
    vcfgz="results/${sample}.vcf.gz"
    bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "$vcfgz" >> "$tmp"
  done
  mv "$tmp" "$collapsed"
fi

exit 0