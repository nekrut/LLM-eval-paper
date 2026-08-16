#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)
REF="data/ref/chrM.fa"

mkdir -p results

# 2. Reference indexing (once)
if [[ ! -f "${REF}.fai" ]]; then
  samtools faidx "$REF"
fi
if [[ ! -f "${REF}.bwt" ]]; then
  bwa index "$REF"
fi

for sample in "${SAMPLES[@]}"; do
  fq1="data/raw/${sample}_1.fq.gz"
  fq2="data/raw/${sample}_2.fq.gz"
  bam="results/${sample}.bam"
  bai="${bam}.bai"
  vcf="results/${sample}.vcf"
  vcfgz="${vcf}.gz"
  tbi="${vcfgz}.tbi"

  # 3-4. Alignment + sort
  if [[ ! -f "$bam" || "$fq1" -nt "$bam" || "$fq2" -nt "$bam" ]]; then
    bwa mem -t "$THREADS" \
      -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
      "$REF" "$fq1" "$fq2" \
      | samtools sort -@ "$THREADS" -o "$bam"
  fi

  # 5. BAM indexing
  if [[ ! -f "$bai" || "$bam" -nt "$bai" ]]; then
    samtools index -@ "$THREADS" "$bam"
  fi

  # 6-7. Variant calling, compression, indexing
  if [[ ! -f "$tbi" || "$bam" -nt "$tbi" ]]; then
    lofreq call-parallel --pp-threads "$THREADS" -f "$REF" -o "$vcf" "$bam"
    bgzip -f "$vcf"
    tabix -p vcf "$vcfgz"
  fi
done

# 8. Collapse step
collapsed="results/collapsed.tsv"
need_rebuild=false
if [[ ! -f "$collapsed" ]]; then
  need_rebuild=true
else
  for sample in "${SAMPLES[@]}"; do
    vcfgz="results/${sample}.vcf.gz"
    if [[ -f "$vcfgz" && "$vcfgz" -nt "$collapsed" ]]; then
      need_rebuild=true
    fi
  done
fi

if [[ "$need_rebuild" == true ]]; then
  tmp="results/.collapsed.tsv.tmp"
  printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$tmp"
  for sample in "${SAMPLES[@]}"; do
    vcfgz="results/${sample}.vcf.gz"
    bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "$vcfgz" >> "$tmp"
  done
  mv "$tmp" "$collapsed"
fi