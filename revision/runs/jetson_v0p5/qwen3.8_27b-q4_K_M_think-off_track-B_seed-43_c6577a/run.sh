#!/usr/bin/env bash
set -euo pipefail

THREADS=4
REF=data/ref/chrM.fa
OUTDIR=results
mkdir -p "$OUTDIR"

SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)

if [[ ! -f data/ref/chrM.fa.bwt ]]; then
  bwa index -m 1 "$REF"
fi

for s in "${SAMPLES[@]}"; do
  bam="$OUTDIR/$s.bam"
  if [[ ! -f "$bam" || ! -f "$bam.bai" ]]; then
    bwa mem -t "$THREADS" -M "$REF" "data/raw/${s}_1.fq.gz" "data/raw/${s}_2.fq.gz" \
      | samtools sort -@ "$THREADS" -o "$bam"
    samtools index "$bam"
  fi

  vcf="$OUTDIR/$s.vcf.gz"
  if [[ ! -f "$vcf" || ! -f "$vcf.tbi" ]]; then
    lofreq call --min-bq 20 --min-pl 10 \
      -t "$THREADS" -r "$REF" -o "$vcf" "$bam"
    tabix -p vcf "$vcf"
  fi
done

COLLAPSED="$OUTDIR/collapsed.tsv"
if [[ ! -f "$COLLAPSED" ]]; then
  {
    printf 'sample\tchrom\tpos\tref\talt\taf\n'
    for s in "${SAMPLES[@]}"; do
      bcftools query \
        --no-header \
        -f '%CHROM\t%POS\t%REF\t%ALT\t[%AF]\n' \
        "$OUTDIR/$s.vcf.gz" | awk -v s="$s" 'BEGIN{OFS="\t"} {print s,$1,$2,$3,$4,$5}'
    done
  } > "$COLLAPSED"
fi