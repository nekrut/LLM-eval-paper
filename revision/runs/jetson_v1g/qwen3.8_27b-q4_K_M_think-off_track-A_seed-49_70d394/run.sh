#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)
REF=data/ref/chrM.fa
RAW=data/raw
OUT=results

mkdir -p "$OUT"

if [[ ! -f "${REF}.amb" || ! -f "${REF}.bwt" || ! -f "${REF}.pac" || ! -f "${REF}.sa" ]]; then
  bwa index "$REF"
fi
if [[ ! -f "${REF}.fai" ]]; then
  samtools faidx "$REF"
fi

for s in "${SAMPLES[@]}"; do
  bam="$OUT/$s.bam"
  bai="$bam.bai"
  vcf="$OUT/$s.vcf.gz"
  tbi="$vcf.tbi"

  if [[ ! -f "$tbi" ]]; then
    bwa mem -t "$THREADS" \
      -R "@RG\tID:$s\tSM:$s\tLB:$s\tPL:ILLUMINA" \
      "$REF" "$RAW/${s}_1.fq.gz" "$RAW/${s}_2.fq.gz" \
      | samtools sort -@ "$THREADS" -o "$bam"

    if [[ ! -f "$bai" ]]; then
      samtools index -@ "$THREADS" "$bam"
    fi

    lofreq call-parallel --pp-threads "$THREADS" \
      --ref "$REF" --out "$OUT/$s.vcf" \
      "$bam"

    bgzip -c "$OUT/$s.vcf" > "$vcf"
    rm -f "$OUT/$s.vcf"
    tabix -p vcf "$vcf"
  fi
done

if [[ ! -f "$OUT/collapsed.tsv" ]]; then
  {
    printf 'sample\tchrom\tpos\tref\talt\taf\n'
    for s in "${SAMPLES[@]}"; do
      bcftools query -h -f '' "$OUT/$s.vcf.gz" >/dev/null 2>&1 || true
      bcftools query -f "{$s}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "$OUT/$s.vcf.gz"
    done
  } > "$OUT/collapsed.tsv"
fi