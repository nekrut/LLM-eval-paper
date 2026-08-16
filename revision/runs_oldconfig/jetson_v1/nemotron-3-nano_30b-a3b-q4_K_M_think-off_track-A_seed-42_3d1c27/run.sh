#!/usr/bin/env bash
set -euo pipefail

THREADS=4
mkdir -p results

samples=(M117-bl M117-ch M117C1-bl M117C1-ch)

for sample in "${samples[@]}"; do
  bam="results/${sample}.bam"
  bai="results/${sample}.bam.bai"
  vcf="results/${sample}.vcf.gz"
  tbi="results/${sample}.vcf.gz.tbi"

  if [[ -e "$tbi" ]]; then
    continue
  fi

  if [[ ! -e "$bam" ]]; then
    fq1="data/raw/${sample}_1.fq.gz"
    fq2="data/raw/${sample}_2.fq.gz"
    rg="@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA"

    bwa mem -t "$THREADS" -R "$rg" data/ref/chrM.fa "$fq1" "$fq2" |
      samtools sort -@ "$THREADS" -o "$bam"
  fi

  if [[ ! -e "$bai" ]]; then
    samtools index -@ "$THREADS" "$bam"
  fi

  if [[ ! -e "$vcf" && ! -e "${vcf}.gz" ]]; then
    lofreq call-parallel --pp-threads "$THREADS" -f data/ref/chrM.fa -o results/${sample}.vcf results/${sample}.bam
    bgzip -c "results/${sample}.vcf" > "results/${sample}.vcf.gz"
    rm -f "results/${sample}.vcf"
  fi

  if [[ ! -e "$tbi" ]]; then
    tabix -p vcf "results/${sample}.vcf.gz"
  fi
done

collapsed="results/collapsed.tsv"

if [[ ! -e "$collapsed" || any newer inputs */*.vcf.gz ]]; then
  {
    echo -e "sample\tchrom\tpos\tref\talt\taf"
    for sample in "${samples[@]}"; do
      bcftools query -f 'sample\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "results/${sample}.vcf.gz"
    done
  } > "$collapsed"
fi

exit 0