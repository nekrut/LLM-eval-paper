#!/usr/bin/env bash
set -euo pipefail

THREADS=4
samples=(M117-bl M117-ch M117C1-bl M117C1-ch)
raw_dir=data/raw
ref=data/ref/chrM.fa
out_dir=results

mkdir -p "$out_dir"

needs_update() {
  local target=$1
  shift
  [[ -s $target ]] || return 0
  local dep
  for dep in "$@"; do
    if [[ ! -e $dep ]]; then
      return 0
    fi
    if [[ $dep -nt $target ]]; then
      return 0
    fi
  done
  return 1
}

faidx_needed=0
bwa_index_needed=0
for sample in "${samples[@]}"; do
  fq1="$raw_dir/${sample}_1.fq.gz"
  fq2="$raw_dir/${sample}_2.fq.gz"
  bam="$out_dir/$sample.bam"
  vcfgz="$out_dir/$sample.vcf.gz"

  if needs_update "$bam" "$fq1" "$fq2" "$ref"; then
    faidx_needed=1
    bwa_index_needed=1
  fi

  if needs_update "$vcfgz" "$bam" "$ref"; then
    faidx_needed=1
  fi
done

if [[ $faidx_needed -eq 1 ]]; then
  if [[ ! -s ${ref}.fai ]] || [[ $ref -nt ${ref}.fai ]]; then
    samtools faidx "$ref"
  fi
fi

if [[ $bwa_index_needed -eq 1 ]]; then
  bwa_index_missing=0
  for ext in amb ann bwt pac sa; do
    if [[ ! -s ${ref}.${ext} ]]; then
      bwa_index_missing=1
      break
    fi
  done

  if [[ $bwa_index_missing -eq 1 ]] || [[ $ref -nt ${ref}.pac ]]; then
    bwa index "$ref"
  fi
fi

for sample in "${samples[@]}"; do
  fq1="$raw_dir/${sample}_1.fq.gz"
  fq2="$raw_dir/${sample}_2.fq.gz"
  bam="$out_dir/$sample.bam"
  bai="$out_dir/$sample.bam.bai"
  vcfgz="$out_dir/$sample.vcf.gz"
  tbi="$out_dir/$sample.vcf.gz.tbi"

  if needs_update "$bam" "$fq1" "$fq2" "$ref"; then
    rm -f "$bai"
    tmp_bam="${bam}.tmp"
    rm -f "$tmp_bam"

    bwa mem -t "$THREADS" \
      -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
      "$ref" "$fq1" "$fq2" | samtools sort -@ "$THREADS" -o "$tmp_bam"

    mv "$tmp_bam" "$bam"
  fi

  if needs_update "$bai" "$bam"; then
    samtools index -@ "$THREADS" "$bam"
  fi

  if needs_update "$vcfgz" "$bam" "$ref"; then
    rm -f "$tbi"
    tmp_vcfgz="${vcfgz}.tmp.gz"

    if command -v bgzip >/dev/null 2>&1; then
      tmp_vcf="${vcfgz}.tmp.vcf"
      rm -f "$tmp_vcf" "$tmp_vcfgz"

      lofreq call-parallel --pp-threads "$THREADS" \
        --ref "$ref" \
        --out "$tmp_vcf" \
        "$bam"

      bgzip -c "$tmp_vcf" > "$tmp_vcfgz"
      rm -f "$tmp_vcf"
    else
      rm -f "$tmp_vcfgz"

      lofreq call-parallel --pp-threads "$THREADS" \
        --ref "$ref" \
        --out "$tmp_vcfgz" \
        "$bam"
    fi

    mv "$tmp_vcfgz" "$vcfgz"
  fi

  if needs_update "$tbi" "$vcfgz"; then
    tabix -p vcf "$vcfgz"
  fi
done

tsv="$out_dir/collapsed.tsv"
vcf_files=()
for sample in "${samples[@]}"; do
  vcf_files+=("$out_dir/$sample.vcf.gz")
done

if needs_update "$tsv" "${vcf_files[@]}"; then
  tmp_tsv="${tsv}.tmp"
  rm -f "$tmp_tsv"

  printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$tmp_tsv"

  for sample in "${samples[@]}"; do
    bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" \
      "$out_dir/${sample}.vcf.gz" >> "$tmp_tsv"
  done

  mv "$tmp_tsv" "$tsv"
fi