#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

mkdir -p results

# Reference indexing
[[ -f data/ref/chrM.fa.bwt ]] || bwa index data/ref/chrM.fa
[[ -f data/ref/chrM.fa.fai ]] || samtools faidx data/ref/chrM.fa

for sample in "${SAMPLES[@]}"; do
  bam=results/${sample}.bam
  if [[ ! -f $bam ]]; then
    bwa mem -t "$THREADS" \
      -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
      data/ref/chrM.fa \
      data/raw/${sample}_1.fq.gz \
      data/raw/${sample}_2.fq.gz | \
    samtools sort -@ "$THREADS" -o "$bam" -
  fi

  if [[ ! -f ${bam}.bai ]]; then
    samtools index -@ "$THREADS" "$bam"
  fi

  vcf_tbi=results/${sample}.vcf.gz.tbi
  if [[ ! -f $vcf_tbi ]]; then
    lofreq call-parallel --pp-threads "$THREADS" \
      -f data/ref/chrM.fa \
      -o results/${sample}.vcf \
      "$bam"
    bgzip -f results/${sample}.vcf
    tabix -p vcf results/${sample}.vcf.gz
  fi
done

printf 'sample\tchrom\tpos\tref\talt\taf\n' > results/collapsed.tsv
for sample in "${SAMPLES[@]}"; do
  bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' \
    results/${sample}.vcf.gz | \
    awk -v s=${sample} 'BEGIN{OFS="\t"}{print s,$0}' >> results/collapsed.tsv
done