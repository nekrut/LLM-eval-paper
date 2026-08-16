#!/usr/bin/env bash
set -euo pipefail

THREADS=4
mkdir -p results

samples=(M117-bl M117-ch M117C1-bl M117C1-ch)

for sample in "${samples[@]}"; do
  bam="results/${sample}.bam"
  bai="results/${sample}.bam.bai"
  vcf="results/${sample}.vcf"
  vcf_gz="results/${sample}.vcf.gz"
  tbi="results/${sample}.vcf.gz.tbi"

  if [[ -e "$tbi" ]]; then
    continue
  fi

  fastq1="data/raw/${sample}_1.fq.gz"
  fastq2="data/raw/${sample}_2.fq.gz"
  rg="@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA"

  if [[ -e "$bam" && -e "$bai" && -e "$vcf_gz.tbi" ]]; then
    continue
  fi

  bwa mem -t "$THREADS" -R "${rg}" data/ref/chrM.fa "$fastq1" "$fastq2" |
    samtools sort -@ "$THREADS" -o "$bam"

  samtools index -@ "$THREADS" "$bam"

  lofreq call-parallel --pp-threads "$THREADS" -f data/ref/chrM.fa -o "$vcf" "$bam"
  bgzip -c "$vcf" > "$vcf_gz"
  tabix -p vcf "$vcf_gz"
  rm -f "$vcf"

done

input_tsv="results/collapsed.tsv"
if [[ ! -e "$input_tsv" || any newer than "$input_tsv" ]]; then
  {
    printf "sample\tchrom\tpos\tref\talt\taf\n"
    for sample in "${samples[@]}"; do
      bcftools query -f '{sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "results/${sample}.vcf.gz"
    done
  } > "$input_tsv"
} || true

exit 0