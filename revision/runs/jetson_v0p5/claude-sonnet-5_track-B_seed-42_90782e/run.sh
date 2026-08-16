#!/usr/bin/env bash
set -euo pipefail

THREADS=4
RAW="data/raw"
REF="data/ref/chrM.fa"
OUT="results"

mkdir -p "$OUT"

# ---- index reference (idempotent) ----
if [[ ! -f "${REF}.bwt" ]]; then
  bwa index "$REF"
fi
if [[ ! -f "${REF}.fai" ]]; then
  samtools faidx "$REF"
fi

SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)

for sample in "${SAMPLES[@]}"; do
  bam="$OUT/${sample}.bam"
  bai="$OUT/${sample}.bam.bai"
  vcf="$OUT/${sample}.vcf.gz"
  tbi="$OUT/${sample}.vcf.gz.tbi"

  if [[ -s "$bam" && -s "$bai" && -s "$vcf" && -s "$tbi" ]]; then
    continue
  fi

  r1="$RAW/${sample}_1.fq.gz"
  r2="$RAW/${sample}_2.fq.gz"

  rg="@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA"

  bwa mem -t "$THREADS" -R "$rg" "$REF" "$r1" "$r2" \
    | samtools sort -@ "$THREADS" -o "$bam" -
  samtools index "$bam"

  iq_bam="$OUT/.${sample}.indelqual.bam"
  lofreq indelqual --dindel -f "$REF" -o "$iq_bam" "$bam"
  samtools index "$iq_bam"

  raw_vcf="$OUT/.${sample}.raw.vcf"
  lofreq call --call-indels -f "$REF" -o "$raw_vcf" "$iq_bam"

  bcftools view "$raw_vcf" -Oz -o "$vcf"
  tabix -f -p vcf "$vcf"

  rm -f "$iq_bam" "${iq_bam}.bai" "$raw_vcf"
done

# ---- collapsed table ----
tmp_collapsed="$OUT/.collapsed.tsv.tmp"
: > "$tmp_collapsed"

for sample in "${SAMPLES[@]}"; do
  vcf="$OUT/${sample}.vcf.gz"
  bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "$vcf" \
    | awk -v s="$sample" 'BEGIN{OFS="\t"}{print s,$1,$2,$3,$4,$5}' >> "$tmp_collapsed"
done

{
  printf 'sample\tchrom\tpos\tref\talt\taf\n'
  cat "$tmp_collapsed"
} > "$OUT/collapsed.tsv"

rm -f "$tmp_collapsed"