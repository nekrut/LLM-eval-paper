#!/usr/bin/env bash
set -euo pipefail

THREADS=4

# Ensure results directory exists
mkdir -p results

# Index reference if necessary
if [ ! -f data/ref/chrM.fa.bwt ]; then
  bwa index data/ref/chrM.fa
fi
if [ ! -f data/ref/chrM.fa.fai ]; then
  samtools faidx data/ref/chrM.fa
fi

samples=(M117-bl M117-ch M117C1-bl M117C1-ch)

for sample in "${samples[@]}"; do
  bam=results/${sample}.bam
  bai=results/${sample}.bai
  vcf=results/${sample}.vcf.gz
  tbi=results/${sample}.vcf.gz.tbi

  # Skip if all outputs already exist
  if [ -f "$bam" ] && [ -f "$bai" ] && [ -f "$vcf" ] && [ -f "$tbi" ]; then
    continue
  fi

  fq1=data/raw/${sample}_1.fq.gz
  fq2=data/raw/${sample}_2.fq.gz

  # Map reads and sort BAM
  bwa mem -t $THREADS data/ref/chrM.fa "$fq1" "$fq2" | \
    samtools view -bS - | \
    samtools sort -@ $THREADS -o "$bam"

  samtools index -@ $THREADS "$bam"

  # Call variants with lofreq and compress
  lofreq call -f data/ref/chrM.fa -q 20 -Q 30 -m 2 -p 0.001 "$bam" | \
    bcftools view -O z -o "$vcf"

  tabix -p vcf "$vcf"
done

# Create collapsed table if not present
if [ ! -f results/collapsed.tsv ]; then
  tmp=$(mktemp)
  for sample in "${samples[@]}"; do
    bcftools query -f '%CHROM\t%POS\t%REF\t%ALT[%INFO/AF]\t' results/${sample}.vcf.gz | \
      awk -v s="$sample" '{print s"\t"$0}' >> "$tmp"
  done
  printf "sample\tchrom\tpos\tref\talt\taf\n" > results/collapsed.tsv
  cat "$tmp" >> results/collapsed.tsv
  rm "$tmp"
fi

exit 0