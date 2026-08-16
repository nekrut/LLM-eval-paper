#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)
REF=data/ref/chrM.fa
RAW=data/raw
OUT=results

mkdir -p "$OUT"

if [[ ! -f "${REF}.fai" ]]; then
  samtools faidx "$REF"
fi

if [[ ! -f "${REF}.amb" || ! -f "${REF}.ann" || ! -f "${REF}.bwt" || ! -f "${REF}.pac" || ! -f "${REF}.sa" ]]; then
  bwa index "$REF"
fi

for s in "${SAMPLES[@]}"; do
  bam="${OUT}/${s}.bam"
  bai="${bam}.bai"
  vcf="${OUT}/${s}.vcf"
  vcfgz="${vcf}.gz"
  tbi="${vcfgz}.tbi"
  fq1="${RAW}/${s}_1.fq.gz"
  fq2="${RAW}/${s}_2.fq.gz"

  if [[ -f "$bam" && -f "$bai" ]]; then
    :
  else
    bwa mem -t "${THREADS}" \
      -R "@RG\tID:${s}\tSM:${s}\tLB:${s}\tPL:ILLUMINA" \
      "$REF" "$fq1" "$fq2" | samtools sort -@ "${THREADS}" -o "$bam"
    samtools index -@ "${THREADS}" "$bam"
  fi

  if [[ ! -f "$vcfgz" || ! -f "$tbi" ]]; then
    lofreq call-parallel --pp-threads "${THREADS}" -f "$REF" -o "$vcf" "$bam"
    bgzip -c "$vcf" > "$vcfgz"
    rm -f "$vcf"
    tabix -p vcf "$vcfgz"
  fi
done

COLLAPSED="${OUT}/collapsed.tsv"
need=0
for s in "${SAMPLES[@]}"; do
  vcfgz="${OUT}/${s}.vcf.gz"
  if [[ ! -f "$COLLAPSED" || "$vcfgz" -nt "$COLLAPSED" ]]; then
    need=1
    break
  fi
done

if [[ "${need}" == "1" ]]; then
  {
    printf 'sample\tchrom\tpos\tref\talt\taf\n'
    for s in "${SAMPLES[@]}"; do
      bcftools query -f "${s}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "${OUT}/${s}.vcf.gz"
    done
  } > "$COLLAPSED"
fi