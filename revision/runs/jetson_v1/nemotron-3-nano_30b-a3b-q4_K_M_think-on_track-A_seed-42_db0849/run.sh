#!/usr/bin/env bash
set -euo pipefail

THREADS=4
samples=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

# Exit early if all required outputs already exist
all_done=1
for s in "${samples[@]}"; do
  for ext in bam bai vcf.gz tbi; do
    if [[ ! -e results/${s}.${ext} ]]; then
      all_done=0
      break 2
    fi
  done
done
if [[ $all_done -eq 1 && -e results/collapsed.tsv ]]; then
  exit 0
fi

mkdir -p results

# Index reference once
if [[ ! -e data/ref/chrM.fa.fai ]]; then
  samtools faidx data/ref/chrM.fa
  bwa index data/ref/chrM.fa
fi

for sample in "${samples[@]}"; do
  # Skip if final artifacts already present
  if [[ -e results/${sample}.bam.bai && -e results/${sample}.vcf.gz.tbi ]]; then
    continue
  fi

  # Align with bwa mem and sort to BAM
  bwa mem -t ${THREADS} -R "@RG\\tID:${sample}\\tSM:${sample}\\tLB:${sample}\\tPL:ILLUMINA" \
    data/ref/chrM.fa \
    data/raw/${sample}_1.fq.gz \
    data/raw/${sample}_2.fq.gz |
  samtools sort -@ ${THREADS} -o results/${sample}.bam

  # Index BAM
  samtools index -@ ${THREADS} results/${sample}.bam

  # Variant calling with lofreq
  lofreq call-parallel --pp-threads ${THREADS} -f data/ref/chrM.fa \
    -o results/${sample}.vcf results/${sample}.bam

  # Compress VCF and index
  bgzip -c results/${sample}.vcf > results/${sample}.vcf.gz
  tabix -p vcf results/${sample}.vcf.gz

  # Remove intermediate uncompressed VCF
  rm -f results/${sample}.vcf
done

# Build or rebuild collapsed.tsv only when necessary
if [[ ! -e results/collapsed.tsv ]]; then
  {
    echo -e "sample\tchrom\tpos\tref\talt\taf"
    for s in "${samples[@]}"; do
      bcftools query -f '{s}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' results/${s}.vcf.gz
    done
  } > results/collapsed.tsv
else
  need_rebuild=0
  for s in "${samples[@]}"; do
    if [[ results/${s}.vcf.gz -nt results/collapsed.tsv ]]; then
      need_rebuild=1; break;
    fi
  done
  if [[ $need_rebuild -eq 1 ]]; then
    {
      echo -e "sample\tchrom\tpos\tref\talt\taf"
      for s in "${samples[@]}"; do
        bcftools query -f '{s}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' results/${s}.vcf.gz
      done
    } > results/collapsed.tsv
  fi
fi