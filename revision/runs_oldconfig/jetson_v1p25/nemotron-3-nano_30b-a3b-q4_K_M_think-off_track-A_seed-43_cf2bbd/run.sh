#!/usr/bin/env bash
set -euo pipefail
THREADS=4
mkdir -p results
samples=(M117-bl M117-ch M117C1-bl M117C1-ch)
for sample in "${samples[@]}"; do
  if [[ ! -f "results/${sample}.vcf.gz.tbi" ]]; then
    ref="data/ref/chrM.fa"
    index_prefix="${ref}.fai ${ref}.amb ${ref}.ann ${ref}.bwt ${ref}.pac ${ref}.sa"
    for idx in $index_prefix; do
      if [[ ! -f "$idx" ]]; then
        samtools faidx "$ref"
        bwa index "$ref"
      fi
    done
    fastq1="data/raw/${sample}_1.fq.gz"
    fastq2="data/raw/${sample}_2.fq.gz"
    rg="@RG\\tID:${sample}\\tSM:${sample}\\tLB:${sample}\\tPL:ILLUMINA"
    bwa mem -t "$THREADS" -R "$rg" "$ref" "$fastq1" "$fastq2" |
      samtools sort -@ "$THREADS" -o "results/${sample}.bam"
    samtools index -@ "$THREADS" "results/${sample}.bam"
    lofreq call-parallel --pp-threads "$THREADS" -f "$ref" -o "results/${sample}.vcf" "results/${sample}.bam"
    bgzip -c "results/${sample}.vcf" > "results/${sample}.vcf.gz"
    tabix -p vcf "results/${sample}.vcf.gz"
    rm -f "results/${sample}.vcf"
  fi
done
if [[ ! -f results/collapsed.tsv || any newer than results/*.vcf.gz ]]; then
  {
    echo -e "sample\tchrom\tpos\tref\talt\taf"
    for sample in "${samples[@]}"; do
      bcftools query -f '{sample}\\t%CHROM\\t%POS\\t%REF\\t%ALT\\t%INFO/AF\\n' results/${sample}.vcf.gz
    done
  } > results/collapsed.tsv
fi