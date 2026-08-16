#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)

REF="data/ref/chrM.fa"
RESULTS="results"

mkdir -p "$RESULTS"

is_stale() {
  local target="$1"; shift
  if [[ ! -f "$target" ]]; then
    return 0
  fi
  local dep
  for dep in "$@"; do
    if [[ "$dep" -nt "$target" ]]; then
      return 0
    fi
  done
  return 1
}

all_exist() {
  local f
  for f in "$@"; do
    [[ -f "$f" ]] || return 1
  done
  return 0
}

# --- Reference indexing (once) ---
if is_stale "${REF}.fai" "$REF"; then
  samtools faidx "$REF"
fi

BWA_INDEX_FILES=("${REF}.amb" "${REF}.ann" "${REF}.bwt" "${REF}.pac" "${REF}.sa")
if ! all_exist "${BWA_INDEX_FILES[@]}"; then
  bwa index "$REF"
fi

# --- Per-sample processing ---
for sample in "${SAMPLES[@]}"; do
  fq1="data/raw/${sample}_1.fq.gz"
  fq2="data/raw/${sample}_2.fq.gz"
  bam="${RESULTS}/${sample}.bam"
  bai="${bam}.bai"
  vcf="${RESULTS}/${sample}.vcf"
  vcfgz="${vcf}.gz"
  tbi="${vcfgz}.tbi"

  if is_stale "$bam" "$fq1" "$fq2" "${REF}.bwt" "${REF}.fai"; then
    rg="@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA"
    bwa mem -t "$THREADS" -R "$rg" "$REF" "$fq1" "$fq2" \
      | samtools sort -@ "$THREADS" -o "$bam"
  fi

  if is_stale "$bai" "$bam"; then
    samtools index -@ "$THREADS" "$bam"
  fi

  if is_stale "$tbi" "$bam" "$bai"; then
    rm -f "$vcfgz" "$tbi" "$vcf"
    lofreq call-parallel --pp-threads "$THREADS" -f "$REF" -o "$vcf" "$bam"
    bgzip "$vcf"
    tabix -p vcf "$vcfgz"
  fi
done

# --- Collapse step ---
collapsed="${RESULTS}/collapsed.tsv"
vcfgzs=()
for sample in "${SAMPLES[@]}"; do
  vcfgzs+=("${RESULTS}/${sample}.vcf.gz")
done

if is_stale "$collapsed" "${vcfgzs[@]}"; then
  tmp_collapsed="${collapsed}.tmp"
  {
    printf 'sample\tchrom\tpos\tref\talt\taf\n'
    for sample in "${SAMPLES[@]}"; do
      bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "${RESULTS}/${sample}.vcf.gz"
    done
  } > "$tmp_collapsed"
  mv "$tmp_collapsed" "$collapsed"
fi