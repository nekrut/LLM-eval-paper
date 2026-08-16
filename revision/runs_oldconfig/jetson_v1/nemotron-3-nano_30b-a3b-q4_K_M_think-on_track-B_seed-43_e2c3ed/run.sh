#!/usr/bin/env bash
set -euo pipefail

THREADS=4
samples=(M117-bl M117-ch M117C1-bl M117C1-ch)

mkdir -p results

# Idempotency check: if all final outputs exist, exit successfully
all_exist=true
for s in "${samples[@]}"; do
  for ext in .bam .bai .vcf.gz .tbi; do
    if [[ ! -e "results/${s}${ext}" ]]; then
      all_exist=false
    fi
  done
done
if [[ "$all_exist" == true && -e results/collapsed.tsv ]]; then
  exit 0
fi

# Mapping each sample
for s in "${samples[@]}"; do
  fastq1="data/raw/${s}_1.fq.gz"
  fastq2="data/raw/${s}_2.fq.gz"
  bam="results/${s}.bam"

  if [[ -e "$bam" && -e "${bam}.bai" ]]; then
    continue
  fi

  bwa mem -t "$THREADS" data/ref/chrM.fa "$fastq1" "$fastq2" |
    samtools view -@ "$THREADS" -b -o "$bam"
  samtools index "$bam"
done

# Variant calling per sample
for s in "${samples[@]}"; do
  bam="results/${s}.bam"
  vcfgz="results/${s}.vcf.gz"

  if [[ -e "$vcfgz" && -e "${vgcz}.tbi" ]]; then
    continue
  fi

  samtools mpileup -f data/ref/chrM.fa -Ou "$bam" |
    bcftools call -c -Oz -o "$vgcz"
  tabix -p vcf "$vgcz"
done

# Build collapsed.tsv (sample chrom pos ref alt af)
{
  printf "sample\tchrom\tpos\tref\talt\taf\n"
  for s in "${samples[@]}"; do
    bcftools query -f '%CHROM\t%POS\t%REF\t%ALT[\t][%AF]\n' "results/${s}.vcf.gz" |
      while IFS= read -r line; do
        printf "%s\t%s\n" "$s" "$line"
      done
  done
} > results/collapsed.tsv

exit 0