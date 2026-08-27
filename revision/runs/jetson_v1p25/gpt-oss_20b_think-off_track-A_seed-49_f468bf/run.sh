#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

mkdir -p results

REF="data/ref/chrM.fa"
if [ ! -f "${REF}.fai" ]; then
  samtools faidx "$REF"
fi
if [ ! -f "${REF}.amb" ]; then
  bwa index "$REF"
fi

for sample in "${SAMPLES[@]}"; do
  FASTQ1="data/raw/${sample}_1.fq.gz"
  FASTQ2="data/raw/${sample}_2.fq.gz"
  BAM="results/${sample}.bam"
  BAI="results/${sample}.bam.bai"
  VCF="results/${sample}.vcf"
  VCFZ="results/${sample}.vcf.gz"
  TBZ="results/${sample}.vcf.gz.tbi"

  if [ ! -f "$BAM" ] || \
     ( [ "$FASTQ1" -nt "$BAM" ] || [ "$FASTQ2" -nt "$BAM" ] ); then
    bwa mem -t "$THREADS" -R "@RG\\tID:${sample}\\tSM:${sample}\\tLB:${sample}\\tPL:ILLUMINA" \
      "$REF" "$FASTQ1" "$FASTQ2" | samtools sort -@ "$THREADS" -o "$BAM"
  fi

  if [ ! -f "$BAI" ] || [ "$BAM" -nt "$BAI" ]; then
    samtools index -@ "$THREADS" "$BAM"
  fi

  if [ ! -f "$VCF" ] || [ "$BAM" -nt "$VCF" ]; then
    lofreq call-parallel --pp-threads "$THREADS" -f "$REF" -o "$VCF" "$BAM"
  fi

  if [ ! -f "$VCFZ" ] || [ "$VCF" -nt "$VCFZ" ]; then
    if command -v bgzip >/dev/null 2>&1; then
      bgzip -c "$VCF" > "$VCFZ"
    else
      bcftools view -O z -o "$VCFZ" "$VCF"
    fi
    rm -f "$VCF"
  fi

  if [ ! -f "$TBZ" ] || [ "$VCFZ" -nt "$TBZ" ]; then
    tabix -p vcf "$VCFZ"
  fi
done

COLLAPSED="results/collapsed.tsv"
REBUILD=false
if [ ! -f "$COLLAPSED" ]; then
  REBUILD=true
else
  for sample in "${SAMPLES[@]}"; do
    VCFZ="results/${sample}.vcf.gz"
    if [ "$VCFZ" -nt "$COLLAPSED" ]; then
      REBUILD=true
      break
    fi
  done
fi

if $REBUILD; then
  {
    printf "sample\tchrom\tpos\tref\talt\taf\n"
    for sample in "${SAMPLES[@]}"; do
      VCFZ="results/${sample}.vcf.gz"
      while IFS= read -r line; do
        printf '%s\t%s\n' "$sample" "$line"
      done < <(bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "$VCFZ")
    done
  } > "$COLLAPSED"
fi

exit 0