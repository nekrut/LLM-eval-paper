#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)

mkdir -p results

if [[ ! -f data/ref/chrM.fa.fai ]]; then
  samtools faidx data/ref/chrM.fa
fi
if [[ ! -f data/ref/chrM.fa.pac ]]; then
  bwa index data/ref/chrM.fa
fi

for sample in "${SAMPLES[@]}"; do
  bam="results/${sample}.bam"
  bai="${bam}.bai"
  vcf_gz="results/${sample}.vcf.gz"
  tbi="${vcf_gz}.tbi"

  if [[ ! -s "$tbi" ]]; then
    bwa mem -t "${THREADS}" \
      -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
      data/ref/chrM.fa \
      "data/raw/${sample}_1.fq.gz" \
      "data/raw/${sample}_2.fq.gz" | samtools sort -@ "${THREADS}" -o "$bam"

    if [[ ! -s "$bai" ]]; then
      samtools index -@ "${THREADS}" "$bam"
    fi

    lofreq call-parallel --pp-threads 4 -f data/ref/chrM.fa -o "results/${sample}.vcf" "$bam"

    bgzip -c "results/${sample}.vcf" > "$vcf_gz"
    rm -f "results/${sample}.vcf"

    tabix -p vcf "$vcf_gz"
  fi
done

if [[ ! -s results/collapsed.tsv ]] || \
   [[ -n "$(find "${SAMPLES[@]/#/%.vcf.gz}" -newer results/collapsed.tsv -print -quit 2>/dev/null)" ]]; then
  {
    printf 'sample\tchrom\tpos\tref\talt\taf\n'
    for sample in "${SAMPLES[@]}"; do
      bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "results/${sample}.vcf.gz"
    done
  } > results/collapsed.tsv
fi