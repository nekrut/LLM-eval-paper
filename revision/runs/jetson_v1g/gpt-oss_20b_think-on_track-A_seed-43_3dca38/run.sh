#!/usr/bin/env bash
set -euo pipefail

THREADS=4
samples=(M117-bl M117-ch M117C1-bl M117C1-ch)

mkdir -p results

# Reference indexing
if [ ! -f data/ref/chrM.fa.bwt ]; then
  samtools faidx data/ref/chrM.fa
  bwa index data/ref/chrM.fa
fi

for sample in "${samples[@]}"; do
  bam=results/${sample}.bam
  bai=results/${sample}.bai
  vcf_tbi=results/${sample}.vcf.gz.tbi

  # Alignment and sorting
  if [ ! -f "$bam" ] || [ ! -f "$bai" ]; then
    bwa mem -t $THREADS \
      -R "@RG\\tID:${sample}\\tSM:${sample}\\tLB:${sample}\\tPL:ILLUMINA" \
      data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz |
      samtools sort -@ $THREADS -o "$bam"
    samtools index -@ $THREADS "$bam"
  fi

  # Variant calling and compression
  if [ ! -f "$vcf_tbi" ]; then
    lofreq call-parallel --pp-threads $THREADS --verbose \
      --ref data/ref/chrM.fa --out results/${sample}.vcf \
      --sig --bonf \
      "$bam"
    bcftools view -Oz -o results/${sample}.vcf.gz results/${sample}.vcf
    tabix -p vcf results/${sample}.vcf.gz
    rm results/${sample}.vcf
  fi
done

# Collapse step
collapsed=results/collapsed.tsv
needs_collapse=false
if [ ! -f "$collapsed" ]; then
  needs_collapse=true
else
  for sample in "${samples[@]}"; do
    if [ -n "$(find results/${sample}.vcf.gz -newer $collapsed)" ]; then
      needs_collapse=true
      break
    fi
  done
fi

if $needs_collapse; then
  tmp=$(mktemp)
  for sample in "${samples[@]}"; do
    bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" results/${sample}.vcf.gz >> "$tmp"
  done
  printf "sample\tchrom\tpos\tref\talt\taf\n" > "$collapsed"
  cat "$tmp" >> "$collapsed"
  rm "$tmp"
fi

exit 0