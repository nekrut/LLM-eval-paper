#!/usr/bin/env bash
set -euo pipefail

THREADS=4
REF=data/ref/chrM.fa
OUTDIR=results
mkdir -p "$OUTDIR"

if [[ ! -f data/ref/chrM.fa.fai ]]; then
  samtools faidx "$REF"
fi

SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)

for s in "${SAMPLES[@]}"; do
  bam="$OUTDIR/$s.bam"
  if [[ ! -f "$bam.bai" ]]; then
    bwa mem -t "$THREADS" -R "@RG\tID:$s\tSM:$s" \
      "$REF" "data/raw/${s}_1.fq.gz" "data/raw/${s}_2.fq.gz" |
      samtools sort -@ "$THREADS" -o "$bam"
    samtools index "$bam"
  fi

  vcf="$OUTDIR/$s.vcf.gz"
  if [[ ! -f "$vcf.tbi" ]]; then
    lofreq call --min-cov 10 -t "$THREADS" \
      -o "$vcf" -r "$REF" "$bam"
    tabix -p vcf "$vcf"
  fi
done

COLLAPSED="$OUTDIR/collapsed.tsv"
if [[ ! -f "$COLLAPSED" ]]; then
  {
    printf 'sample\tchrom\tpos\tref\talt\taf\n'
    for s in "${SAMPLES[@]}"; do
      bcftools query -H -f '%CHROM\t%POS\t%REF\t%ALT\t%AF[0]\n' \
        "$OUTDIR/$s.vcf.gz" |
        awk -v s="$s" '{print s"\t"$1"\t"$2"\t"$3"\t"$4"\t"$5}'
    done
  } > "$COLLAPSED"
fi