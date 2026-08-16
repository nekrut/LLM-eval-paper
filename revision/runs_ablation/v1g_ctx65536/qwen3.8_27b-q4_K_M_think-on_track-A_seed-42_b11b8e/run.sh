#!/usr/bin/env bash
set -euo pipefail

THREADS=4
samples=(M117-bl M117-ch M117C1-bl M117C1-ch)
ref=data/ref/chrM.fa
raw_dir=data/raw
res=results
fai="$ref.fai"
bwa_index_files=("$ref.amb" "$ref.ann" "$ref.bwt" "$ref.pac" "$ref.sa")

mkdir -p "$res"

needs_update() {
  local out=$1
  shift
  [[ -s $out ]] || return 0
  local input
  for input in "$@"; do
    if [[ $input -nt $out ]]; then
      return 0
    fi
  done
  return 1
}

vcf_files=()
for s in "${samples[@]}"; do
  vcf_files+=("$res/$s.vcf.gz")
done

if [[ ! -e $fai || $ref -nt $fai ]]; then
  samtools faidx "$ref"
fi

need_bwa=1
for f in "${bwa_index_files[@]}"; do
  if [[ ! -e $f || $ref -nt $f ]]; then
    need_bwa=0
    break
  fi
done
bwa_changed=0
if [[ $need_bwa -eq 0 ]]; then
  bwa index "$ref"
  bwa_changed=1
fi

any_vcf_built=0
for s in "${samples[@]}"; do
  r1="$raw_dir/${s}_1.fq.gz"
  r2="$raw_dir/${s}_2.fq.gz"
  bam="$res/$s.bam"
  bai="$bam.bai"
  vcf="$res/$s.vcf.gz"
  tbi="$vcf.tbi"

  bam_built=0
  if [[ $bwa_changed -eq 1 ]] || needs_update "$bam" "$r1" "$r2" "$ref" "${bwa_index_files[@]}"; then
    bwa mem -t "$THREADS" \
      -R "@RG\tID:${s}\tSM:${s}\tLB:${s}\tPL:ILLUMINA" \
      "$ref" "$r1" "$r2" | samtools sort -@ "$THREADS" -o "$bam"
    bam_built=1
  fi

  if [[ $bam_built -eq 1 ]]; then
    samtools index -@ "$THREADS" "$bam"
  elif needs_update "$bai" "$bam"; then
    samtools index -@ "$THREADS" "$bam"
  fi

  vcf_built=0
  if [[ $bam_built -eq 1 ]] || needs_update "$vcf" "$bam" "$ref" "$fai"; then
    lofreq call-parallel --pp-threads "$THREADS" \
      --ref "$ref" \
      --out "$vcf" \
      "$bam"
    vcf_built=1
    any_vcf_built=1
  fi

  if [[ $vcf_built -eq 1 ]]; then
    tabix -p vcf "$vcf"
  elif needs_update "$tbi" "$vcf"; then
    tabix -p vcf "$vcf"
  fi
done

collapsed="$res/collapsed.tsv"
if [[ $any_vcf_built -eq 1 ]] || needs_update "$collapsed" "${vcf_files[@]}"; then
  outputs=()
  for s in "${samples[@]}"; do
    out="$(bcftools query -f "${s}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "$res/$s.vcf.gz")"
    if [[ -n $out ]]; then
      outputs+=("$out")
    fi
  done
  {
    printf 'sample\tchrom\tpos\tref\talt\taf\n'
    if [[ ${#outputs[@]} -gt 0 ]]; then
      for out in "${outputs[@]}"; do
        printf '%s\n' "$out"
      done
    fi
  } > "$collapsed"
fi

exit 0