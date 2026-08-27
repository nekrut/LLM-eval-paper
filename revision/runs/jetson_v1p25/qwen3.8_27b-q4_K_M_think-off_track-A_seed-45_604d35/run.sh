#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)
REF=data/ref/chrM.fa
RAW=data/raw
OUT=results

mkdir -p "$OUT"

if [[ ! -f "${REF}.fai" || ! -f "${REF}.amb" ]]; then
  samtools faidx "$REF"
fi
if [[ ! -f "${REF}.bwt" ]]; then
  bwa index "$REF"
fi

for s in "${SAMPLES[@]}"; do
  f1="${RAW}/${s}_1.fq.gz"
  f2="${RAW}/${s}_2.fq.gz"
  bam="${OUT}/${s}.bam"
  bai="${OUT}/${s}.bam.bai"
  vcf="${OUT}/${s}.vcf"
  vcfgz="${OUT}/${s}.vcf.gz"
  tbi="${OUT}/${s}.vcf.gz.tbi"

  if [[ -s "$tbi" && ! ( "$f1" -nt "$tbi" || "$f2" -nt "$tbi" ) ]]; then
    continue
  fi

  bwa mem -t "$THREADS" \
    -R "@RG\tID:${s}\tSM:${s}\tLB:${s}\tPL:ILLUMINA" \
    "$REF" "$f1" "$f2" | samtools sort -@ "$THREADS" -o "$bam"

  samtools index -@ "$THREADS" "$bam"

  lofreq call-parallel --pp-threads "$THREADS" -f "$REF" -o "$vcf" "$bam"

  bgzip -c "$vcf" > "${vcfgz}.tmp"
  mv "${vcfgz}.tmp" "$vcfgz"
  rm -f "$vcf"

  tabix -p vcf "$vcfgz"
done

if [[ ! -s "${OUT}/collapsed.tsv" || ( \
      "${OUT}/${SAMPLES[0]}.vcf.gz" -nt "${OUT}/collapsed.tsv" || \
      "${OUT}/${SAMPLES[1]}.vcf.gz" -nt "${OUT}/collapsed.tsv" || \
      "${OUT}/${SAMPLES[2]}.vcf.gz" -nt "${OUT}/collapsed.tsv" || \
      "${OUT}/${SAMPLES[3]}.vcf.gz" -nt "${OUT}/collapsed.tsv" ) ]]; then
  {
    printf 'sample\tchrom\tpos\tref\talt\taf\n'
    for s in "${SAMPLES[@]}"; do
      bcftools query -f "${s}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "${OUT}/${s}.vcf.gz"
    done
  } > "${OUT}/collapsed.tsv.tmp"
  mv "${OUT}/collapsed.tsv.tmp" "${OUT}/collapsed.tsv"
fi