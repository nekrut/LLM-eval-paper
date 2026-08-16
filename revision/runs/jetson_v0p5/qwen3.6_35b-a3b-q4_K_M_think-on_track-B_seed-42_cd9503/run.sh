#!/usr/bin/env bash
set -euo pipefail

REF="data/ref/chrM.fa"
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)

mkdir -p results

if [ ! -f data/ref/chrM.fa.bwt ]; then
  bwa index "$REF"
fi
if [ ! -f data/ref/chrM.fa.fai ]; then
  samtools faidx "$REF"
fi

for S in "${SAMPLES[@]}"; do
  BAM="results/${S}.bam"
  VCF_GZ="results/${S}.vcf.gz"

  if [ ! -f "$BAM" ]; then
    bwa mem -t 4 "$REF" "data/raw/${S}_1.fq.gz" "data/raw/${S}_2.fq.gz" | \
      samtools sort -@ 4 -o "$BAM" -
  fi

  if [ ! -f "${BAM}.bai" ]; then
    samtools index "$BAM"
  fi

  VCF="results/${S}.vcf"
  if [ ! -f "$VCF_GZ" ]; then
    lofreq call-parallel -f "$REF" -d "$BAM" -o "$VCF" --pass-only
    bgzip "$VCF"
  fi

  if [ ! -f "${VCF_GZ}.tbi" ]; then
    tabix -p vcf "$VCF_GZ"
  fi
done

COLLAPSED="results/collapsed.tsv"
if [ ! -f "$COLLAPSED" ]; then
  printf "sample\tchrom\tpos\tref\talt\taf\n" > "$COLLAPSED"
  for S in "${SAMPLES[@]}"; do
    VCF_GZ="results/${S}.vcf.gz"
    if [ -f "$VCF_GZ" ]; then
      bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO{AF}\n' "$VCF_GZ" | \
        awk -F'\t' '$5 != "." && $5 != "" {print "'"$S"'" "\t" $0}' >> "$COLLAPSED"
    fi
  done
fi