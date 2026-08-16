#!/usr/bin/env bash
set -euo pipefail

samples=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

for sample in "${samples[@]}"; do
  bam="results/${sample}.bam"
  vcfg="results/${sample}.vcf.gz"
  tbi="results/${sample}.tbi"

  if [[ -f "$bam" && -f "$vcfg" && -f "$tbi" ]]; then
    continue
  fi

  mkdir -p results

  bwa mem data/ref/chrM.fa "${sample}_1.fq.gz" "${sample}_2.fq.gz" > "$bam"
  samtools sort -@4 "$bam" -o "$bam"
  samtools index "$bam"

  bcftools view -f 0 "$bam" > results/${sample}.vcf
  gzip results/${sample}.vcf && tabix -p vcf results/${sample}.vcf.gz

done

if [[ ! -f "results/collapsed.tsv" ]]; then
  seqkit aggregate -i results/*.bam -o results/collapsed.tsv -c 0,1,2,3,4,5
fi

exit 0