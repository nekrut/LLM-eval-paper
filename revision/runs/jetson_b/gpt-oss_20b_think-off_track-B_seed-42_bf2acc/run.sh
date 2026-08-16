#!/usr/bin/env bash
set -euo pipefail

THREADS=4
REF="data/ref/chrM.fa"
RAW="data/raw"
OUT="results"

mkdir -p "$OUT"

samples=( M117-bl M117-ch M117C1-bl M117C1-ch )

all_exist=true
for s in "${samples[@]}"; do
  for ext in bam bai vcf.gz tbi; do
    file="$OUT/${s}.${ext}"
    if [ ! -f "$file" ]; then
      all_exist=false
      break 2
    fi
  done
done
if [ "$all_exist" = true ] && [ -f "$OUT/collapsed.tsv" ]; then
  exit 0
fi

if [ ! -f "${REF}.bwt" ] || [ ! -f "${REF}.fai" ]; then
  bwa index "$REF"
  samtools faidx "$REF"
fi

for s in "${samples[@]}"; do
  bam="$OUT/${s}.bam"
  bai="$OUT/${s}.bam.bai"
  vcf="$OUT/${s}.vcf.gz"
  tbi="$OUT/${s}.vcf.gz.tbi"

  if [ ! -f "$bam" ]; then
    bwa mem -t "$THREADS" "$REF" "${RAW}/${s}_1.fq.gz" "${RAW}/${s}_2.fq.gz" |
      samtools view -Sb - | samtools sort -o "$bam"
  fi

  if [ ! -f "$bai" ]; then
    samtools index "$bam"
  fi

  if [ ! -f "$vcf" ]; then
    lofreq call -f "$REF" -b "$bam" | bcftools view -O z -o "$vcf"
  fi

  if [ ! -f "$tbi" ]; then
    tabix -p vcf "$vcf"
  fi
done

if [ ! -f "$OUT/collapsed.tsv" ]; then
  printf "sample\tchrom\tpos\tref\talt\taf\n" > "$OUT/collapsed.tsv"
  for s in "${samples[@]}"; do
    vcf="$OUT/${s}.vcf.gz"
    if [ -f "$vcf" ]; then
      bcftools query -f '%CHROM\t%POS\t%REF\t%ALT[\t%AF]\n' "$vcf" |
        awk -v samp="$s" '{print samp"\t"$0}' >> "$OUT/collapsed.tsv"
    fi
  done
fi

exit 0