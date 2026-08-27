#!/usr/bin/env bash
set -euo pipefail

THREADS=4
samples=(M117-bl M117-ch M117C1-bl M117C1-ch)

mkdir -p results

# Reference indexing
if [[ ! -f data/ref/chrM.fa.bwt ]]; then
  samtools faidx data/ref/chrM.fa
  bwa index data/ref/chrM.fa
fi

is_newer() {
  local out=$1
  shift
  [[ -f $out ]] || return 1
  local out_mtime=$(stat -c %Y "$out")
  for inp in "$@"; do
    [[ -f $inp ]] || return 1
    local inp_mtime=$(stat -c %Y "$inp")
    if (( inp_mtime > out_mtime )); then
      return 1
    fi
  done
  return 0
}

for sample in "${samples[@]}"; do
  raw1=data/raw/${sample}_1.fq.gz
  raw2=data/raw/${sample}_2.fq.gz
  bam=results/${sample}.bam
  bai=results/${sample}.bam.bai
  vcf_uncompressed=results/${sample}.vcf
  vcf_gz=results/${sample}.vcf.gz
  vcf_tbi=results/${sample}.vcf.gz.tbi

  if ! is_newer "$bam" "$raw1" "$raw2"; then
    bwa mem -t $THREADS -R "@RG\\tID:${sample}\\tSM:${sample}\\tLB:${sample}\\tPL:ILLUMINA" data/ref/chrM.fa "$raw1" "$raw2" | \
      samtools sort -@ $THREADS -o "$bam"
  fi

  if ! is_newer "$bai" "$bam"; then
    samtools index -@ $THREADS "$bam"
  fi

  if ! is_newer "$vcf_uncompressed" "$bam" data/ref/chrM.fa; then
    lofreq call-parallel --pp-threads $THREADS -f data/ref/chrM.fa -o "$vcf_uncompressed" "$bam"
  fi

  if ! is_newer "$vcf_gz" "$vcf_uncompressed"; then
    bcftools view -O z -o "$vcf_gz" "$vcf_uncompressed"
    rm -f "$vcf_uncompressed"
  fi

  if ! is_newer "$vcf_tbi" "$vcf_gz"; then
    tabix -p vcf "$vcf_gz"
  fi
done

collapsed=results/collapsed.tsv
tmpfile=$(mktemp)

for sample in "${samples[@]}"; do
  bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" results/${sample}.vcf.gz >> "$tmpfile"
done

if ! is_newer "$collapsed" results/*.vcf.gz; then
  printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed"
  cat "$tmpfile" >> "$collapsed"
fi

rm -f "$tmpfile"

exit 0