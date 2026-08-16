#!/usr/bin/env bash
set -euo pipefail

THREADS=4
REF="data/ref/chrM.fa"
RAW="data/raw"
OUT="results"

mkdir -p "$OUT"

if [[ ! -f "${REF}.bwt" ]]; then
  bwa index "$REF"
fi

if [[ ! -f "${REF}.fai" ]]; then
  samtools faidx "$REF"
fi

SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)

for sample in "${SAMPLES[@]}"; do
  bam="${OUT}/${sample}.bam"
  bai="${bam}.bai"
  vcf_gz="${OUT}/${sample}.vcf.gz"
  tbi="${vcf_gz}.tbi"
  r1="${RAW}/${sample}_1.fq.gz"
  r2="${RAW}/${sample}_2.fq.gz"

  if [[ ! -s "$bam" || ! -s "$bai" ]]; then
    bwa mem -t "$THREADS" \
      -R "@RG\tID:${sample}\tSM:${sample}\tPL:ILLUMINA" \
      "$REF" "$r1" "$r2" \
      | samtools sort -@ "$THREADS" -o "$bam" -
    samtools index "$bam"
  fi

  if [[ ! -s "$vcf_gz" || ! -s "$tbi" ]]; then
    raw_vcf="${OUT}/${sample}.raw.vcf"
    rm -f "$raw_vcf"
    lofreq call-parallel --pp-threads "$THREADS" -f "$REF" -o "$raw_vcf" "$bam"
    bcftools view -Oz -o "$vcf_gz" "$raw_vcf"
    tabix -f -p vcf "$vcf_gz"
    rm -f "$raw_vcf"
  fi
done

collapsed="${OUT}/collapsed.tsv"
tmp_collapsed="${collapsed}.tmp.$$"

{
  printf 'sample\tchrom\tpos\tref\talt\taf\n'
  for sample in "${SAMPLES[@]}"; do
    vcf_gz="${OUT}/${sample}.vcf.gz"
    bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "$vcf_gz" \
      | awk -F'\t' -v s="$sample" 'BEGIN{OFS="\t"} {print s,$1,$2,$3,$4,$5}'
  done
} > "$tmp_collapsed"

mv "$tmp_collapsed" "$collapsed"