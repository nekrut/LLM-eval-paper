#!/usr/bin/env bash
set -euo pipefail

THREADS=4
samples=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

mkdir -p results

# Reference indexing
if [ ! -f data/ref/chrM.fa.fai ]; then
  samtools faidx data/ref/chrM.fa
fi
if [ ! -f data/ref/chrM.fa.bwt ] || [ ! -f data/ref/chrM.fa.ann ]; then
  bwa index data/ref/chrM.fa
fi

# Per-sample processing
for s in "${samples[@]}"; do
  bam=results/${s}.bam
  bai=results/${s}.bam.bai
  vcf_gz=results/${s}.vcf.gz
  tbi=results/${s}.vcf.gz.tbi
  if [ -f "$tbi" ]; then
    continue
  fi

  fq1=data/raw/${s}_1.fq.gz
  fq2=data/raw/${s}_2.fq.gz

  bwa mem -t $THREADS -R "@RG\\tID:${s}\\tSM:${s}\\tLB:${s}\\tPL:ILLUMINA" "$fq1" "$fq2" | \
    samtools sort -@ $THREADS -o "$bam"

  samtools index -@ $THREADS "$bam"

  lofreq call-parallel --pp-threads $THREADS -f data/ref/chrM.fa -o "results/${s}.vcf" "$bam"
  bgzip -c results/${s}.vcf > "$vcf_gz"
  tabix -p vcf "$vcf_gz"
  rm -f results/${s}.vcf
done

# Collapse table
collapsed=results/collapsed.tsv
rebuild=false
if [ ! -f "$collapsed" ]; then
  rebuild=true
else
  for s in "${samples[@]}"; do
    if [ "results/${s}.vcf.gz" -nt "$collapsed" ]; then
      rebuild=true
      break
    fi
  done
fi

if $rebuild; then
  tmp=$(mktemp)
  for s in "${samples[@]}"; do
    bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' results/${s}.vcf.gz | \
      while IFS= read -r line; do
        printf '%s\t%s\n' "$s" "$line"
      done >> "$tmp"
  done
  printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed"
  cat "$tmp" >> "$collapsed"
  rm -f "$tmp"
fi

exit 0