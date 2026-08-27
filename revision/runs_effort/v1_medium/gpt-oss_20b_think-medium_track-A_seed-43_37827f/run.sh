#!/usr/bin/env bash
set -euo pipefail

THREADS=4
samples=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

mkdir -p results

# Reference indexing
if [ ! -f data/ref/chrM.fa.fai ]; then
  samtools faidx data/ref/chrM.fa
fi
if [ ! -f data/ref/chrM.fa.amb ]; then
  bwa index data/ref/chrM.fa
fi

for sample in "${samples[@]}"; do
  bam=results/${sample}.bam
  bai=${bam}.bai
  vcf_gz=results/${sample}.vcf.gz
  tbi=${vcf_gz}.tbi

  if [ -f "$tbi" ]; then
    continue
  fi

  bwa mem -t $THREADS -R "@RG\\tID:${sample}\\tSM:${sample}\\tLB:${sample}\\tPL:ILLUMINA" \
      data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz | \
    samtools sort -@ $THREADS -o "$bam"

  samtools index -@ $THREADS "$bam"

  tmp_vcf=results/${sample}.vcf
  lofreq call-parallel --pp-threads $THREADS -f data/ref/chrM.fa -b "$bam" > "$tmp_vcf"

  samtools bgzip -c "$tmp_vcf" > "$vcf_gz"
  tabix -p vcf "$vcf_gz"
  rm "$tmp_vcf"
done

collapsed=results/collapsed.tsv
rebuild=false
if [ ! -f "$collapsed" ]; then
  rebuild=true
else
  for sample in "${samples[@]}"; do
    vcf_gz=results/${sample}.vcf.gz
    if [ "$vcf_gz" -nt "$collapsed" ]; then
      rebuild=true
      break
    fi
  done
fi

if $rebuild; then
  printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed"
  for sample in "${samples[@]}"; do
    vcf_gz=results/${sample}.vcf.gz
    bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "$vcf_gz" >> "$collapsed"
  done
fi