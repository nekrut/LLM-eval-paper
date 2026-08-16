#!/usr/bin/env bash
set -euo pipefail

THREADS=4
samples=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

mkdir -p results

# Reference indexing (once)
if [ ! -f data/ref/chrM.fa.fai ] || [ ! -f data/ref/chrM.amb ]; then
    samtools faidx data/ref/chrM.fa
    bwa index data/ref/chrM.fa
fi

for sample in "${samples[@]}"; do
  bam=results/${sample}.bam
  bai=results/${sample}.bam.bai
  vcf=results/${sample}.vcf.gz
  tbi=results/${sample}.vcf.gz.tbi

  # Skip downstream steps if BAM already exists (idempotency)
  if [ -e "$bam" ]; then
    continue
  fi

  # Paired-end alignment with bwa mem
  fastq1=data/raw/${sample}_1.fq.gz
  fastq2=data/raw/${sample}_2.fq.gz
  rg="@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA"
  bwa mem -t "$THREADS" -R "$rg" data/ref/chrM.fa "$fastq1" "$fastq2" |
    samtools sort -@ "$THREADS" -o "$bam"

  # Index the sorted BAM
  samtools index -@ "$THREADS" "$bam"

  # Variant calling with lofreq (produces uncompressed VCF in results/)
  lofreq call-parallel --pp-threads "$THREADS" --verbose \
    --ref data/ref/chrM.fa --out "results/${sample}.vcf" \
    "$bam"

  # Compress VCF and create TBI index
  bgzip -c "results/${sample}.vcf" > "$vcf"
  tabix -p vcf "$vcf"
  rm "results/${sample}.vcf"
done

# Collapse all per-sample variant lines into a single TSV
collapsed=results/collapsed.tsv
if [ ! -e "$collapsed" ]; then
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed"
    for sample in "${samples[@]}"; do
        bcftools query -f '{sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "results/${sample}.vcf.gz" >> "$collapsed"
    done
fi