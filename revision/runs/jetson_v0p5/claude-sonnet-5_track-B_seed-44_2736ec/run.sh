#!/usr/bin/env bash
set -euo pipefail

THREADS=4
RAW_DIR="data/raw"
REF="data/ref/chrM.fa"
RESULTS_DIR="results"

mkdir -p "$RESULTS_DIR"

if [[ ! -f "${REF}.bwt" ]]; then
  bwa index "$REF"
fi
if [[ ! -f "${REF}.fai" ]]; then
  samtools faidx "$REF"
fi

SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)

for sample in "${SAMPLES[@]}"; do
  bam="${RESULTS_DIR}/${sample}.bam"
  bai="${bam}.bai"
  vcf_gz="${RESULTS_DIR}/${sample}.vcf.gz"
  vcf_tbi="${vcf_gz}.tbi"

  if [[ -f "$bam" && -f "$bai" && -f "$vcf_gz" && -f "$vcf_tbi" ]]; then
    continue
  fi

  r1="${RAW_DIR}/${sample}_1.fq.gz"
  r2="${RAW_DIR}/${sample}_2.fq.gz"

  if [[ ! -f "$bam" || ! -f "$bai" ]]; then
    raw_bam="${RESULTS_DIR}/${sample}.raw.bam"
    bwa mem -t "$THREADS" -R "@RG\tID:${sample}\tSM:${sample}\tPL:ILLUMINA" "$REF" "$r1" "$r2" \
      | samtools sort -@ "$THREADS" -o "$raw_bam" -
    samtools index "$raw_bam"
    lofreq indelqual --dindel -f "$REF" -o "$bam" "$raw_bam"
    samtools index "$bam"
    rm -f "$raw_bam" "${raw_bam}.bai"
  fi

  if [[ ! -f "$vcf_gz" || ! -f "$vcf_tbi" ]]; then
    raw_vcf="${RESULTS_DIR}/${sample}.vcf"
    rm -f "$raw_vcf" "$vcf_gz" "$vcf_tbi"
    lofreq call --call-indels -f "$REF" -o "$raw_vcf" "$bam"
    bgzip -f "$raw_vcf"
    tabix -f -p vcf "$vcf_gz"
  fi
done

collapsed="${RESULTS_DIR}/collapsed.tsv"
if [[ ! -f "$collapsed" ]]; then
  tmp_collapsed="${collapsed}.tmp"
  printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$tmp_collapsed"
  for sample in "${SAMPLES[@]}"; do
    vcf_gz="${RESULTS_DIR}/${sample}.vcf.gz"
    bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "$vcf_gz" \
      | awk -v s="$sample" 'BEGIN{OFS="\t"}{print s,$1,$2,$3,$4,$5}' >> "$tmp_collapsed"
  done
  mv "$tmp_collapsed" "$collapsed"
fi