#!/usr/bin/env bash
set -euo pipefail

THREADS=4

samples=(M117-bl M117-ch M117C1-bl M117C1-ch)

mkdir -p results

# Check if all outputs exist
all_done=true
for s in "${samples[@]}"; do
  for f in bam bam.bai vcf.gz vcf.gz.tbi; do
    [[ ! -f "results/${s}.${f}" ]] && all_done=false
  done
done
if $all_done && [[ -f results/collapsed.tsv ]]; then
  exit 0
fi

# Process each sample
for s in "${samples[@]}"; do
  need_process=false
  for f in bam bam.bai vcf.gz vcf.gz.tbi; do
    [[ ! -f "results/${s}.${f}" ]] && need_process=true
  done
  if $need_process; then
    bwa mem -t "$THREADS" data/ref/chrM.fa data/raw/"${s}_1.fq.gz" data/raw/"${s}_2.fq.gz" | \
      samtools sort -@ "$THREADS" -o "results/${s}.bam"
    samtools index "results/${s}.bam"

    lofreq call -f data/ref/chrM.fa -m 20 -Q 30 -v "results/${s}.bam" | \
      bcftools view -Oz -o "results/${s}.vcf.gz"
    tabix -p vcf "results/${s}.vcf.gz"
  fi
done

# Generate collapsed.tsv
printf "sample\tchrom\tpos\tref\talt\taf\n" > results/collapsed.tsv
for s in "${samples[@]}"; do
  bcftools query -f '%CHROM\t%POS\t%REF\t%ALT[\t%INFO/AF]\n' "results/${s}.vcf.gz" | \
    while IFS= read -r line; do
      printf "%s\t%s\n" "$s" "$line"
    done >> results/collapsed.tsv
done

exit 0