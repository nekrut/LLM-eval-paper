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
  bam="${OUT}/${s}.bam"
  bai="${bam}.bai"
  vcf_gz="${OUT}/${s}.vcf.gz"
  tbi="${vcf_gz}.tbi"
  f1="${RAW}/${s}_1.fq.gz"
  f2="${RAW}/${s}_2.fq.gz"

  if [[ ! -f "$bai" || "$bam" -nt "$f1" || "$bam" -nt "$f2" ]]; then
    bwa mem -t "${THREADS}" \
      -R "@RG\tID:${s}\tSM:${s}\tLB:${s}\tPL:ILLUMINA" \
      "$REF" "$f1" "$f2" | samtools sort -@ "${THREADS}" -o "$bam"
    samtools index -@ "${THREADS}" "$bam"
  fi

  if [[ ! -f "$tbi" || "$bam" -nt "$vcf_gz" ]]; then
    lofreq call-parallel --pp-threads "${THREADS}" -f "$REF" -o "${OUT}/${s}.vcf" "$bam"
    bgzip -c "${OUT}/${s}.vcf" > "$vcf_gz"
    rm -f "${OUT}/${s}.vcf"
    tabix -p vcf "$vcf_gz"
  fi
done

collapsed="${OUT}/collapsed.tsv"
need=0
for s in "${SAMPLES[@]}"; do
  if [[ ! -f "$collapsed" || "${OUT}/${s}.vcf.gz" -nt "$collapsed" ]]; then
    need=1
    break
  fi
done

if [[ "$need" == "1" ]]; then
  {
    printf 'sample\tchrom\tpos\tref\talt\taf\n'
    for s in "${SAMPLES[@]}"; do
      bcftools query -f "${s}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "${OUT}/${s}.vcf.gz"
    done
  } > "$collapsed"
fi