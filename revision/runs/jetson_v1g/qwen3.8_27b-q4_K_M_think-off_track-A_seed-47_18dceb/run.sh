#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)
REF=data/ref/chrM.fa
RAW=data/raw
OUT=results

mkdir -p "$OUT"

if [[ ! -f "${REF}.amb" || ! -f "${REF}.bwt" || ! -f "${REF}.pac" || ! -f "${REF}.sa" || ! -f "${REF}.ann" ]]; then
  bwa index "$REF"
fi
if [[ ! -f "${REF}.fai" ]]; then
  samtools faidx "$REF"
fi

for s in "${SAMPLES[@]}"; do
  bam="$OUT/${s}.bam"
  bai="$OUT/${s}.bam.bai"
  vcf="$OUT/${s}.vcf.gz"
  tbi="$OUT/${s}.vcf.gz.tbi"
  f1="${RAW}/${s}_1.fq.gz"
  f2="${RAW}/${s}_2.fq.gz"

  if [[ ! -f "$bam" || ! -f "$bai" ]]; then
    bwa mem -t "$THREADS" \
      -R "@RG\tID:${s}\tSM:${s}\tLB:${s}\tPL:ILLUMINA" \
      "$REF" "$f1" "$f2" | samtools sort -@ "$THREADS" -o "$bam"
  fi

  if [[ ! -f "$bai" ]]; then
    samtools index -@ "$THREADS" "$bam"
  fi

  if [[ ! -f "$tbi" || ! -s "$tbi" ]]; then
    lofreq call-parallel --pp-threads "$THREADS" \
      --ref "$REF" \
      --out "$OUT/${s}.vcf" \
      "$bam"
    bgzip -c "$OUT/${s}.vcf" > "$vcf"
    rm -f "$OUT/${s}.vcf"
    tabix -p vcf "$vcf"
  fi
done

COLLAPSED="$OUT/collapsed.tsv"
need_rebuild=0
if [[ ! -f "$COLLAPSED" ]]; then
  need_rebuild=1
else
  for s in "${SAMPLES[@]}"; do
    if [[ "$OUT/${s}.vcf.gz.tbi" -nt "$COLLAPSED" ]]; then
      need_rebuild=1
      break
    fi
  done
fi

if [[ $need_rebuild -eq 1 ]]; then
  {
    printf 'sample\tchrom\tpos\tref\talt\taf\n'
    for s in "${SAMPLES[@]}"; do
      bcftools query -h "$OUT/${s}.vcf.gz" | grep -v '^#' || true
      bcftools query -F AF -f '${CHROM}\t%POS\t%REF\t%ALT\n' "$OUT/${s}.vcf.gz" \
        | awk -v s="$s" '{print s"\t"$0}'
    done
  } > "$COLLAPSED"
fi