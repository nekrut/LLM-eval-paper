#!/usr/bin/env bash
set -euo pipefail

# Ensure output directory exists
mkdir -p results

# Reference preparation (idempotent)
REF="data/ref/chrM.fa"
if [[ ! -f "${REF}.fai" ]]; then
  samtools faidx "$REF"
fi
if [[ ! -f "${REF}.bwt" ]]; then
  bwa index "$REF"
fi

# List of sample prefixes (R1/R2 files are _1.fq.gz and _2.fq.gz)
samples=(M117-bl M117-ch M117C1-bl M117C1-ch)

for samp in "${samples[@]}"; do
  # Define output filenames
  BAM="results/${samp}.bam"
  BAI="${BAM}.bai"
  VCF_GZ="results/${samp}.vcf.gz"
  VCF_TBI="${VCF_GZ}.tbi"

  # Skip if final VCF and its index already exist (idempotent)
  if [[ -f "$VCF_GZ" && -f "$VCF_TBI" ]]; then
    continue
  fi

  # Mapping with BWA MEM to chrM
  bwa mem -t 4 "$REF" "data/raw/${samp}_1.fq.gz" "data/raw/${samp}_2.fq.gz" |
    samtools view -bS - > "${BAM}.tmp"

  # Sort and index BAM (replace only if new)
  if [[ ! -f "$BAM" || "${BAM}.tmp" -nt "$BAM" ]]; then
    samtools sort -@ 4 -o "$BAM" "${BAM}.tmp"
    rm "${BAM}.tmp"
  fi
  if [[ ! -f "$BAI" || "$BAM" -nt "$BAI" ]]; then
    samtools index "$BAM"
  fi

  # Variant calling with LoFreq Star
  lofreq star --call-indels \
    -f "$REF" \
    -r chrM \
    -o "$VCF_GZ" \
    "$BAM"

  # Tabix index the VCF (replace if missing or stale)
  if [[ ! -f "$VCF_TBI" || "$VCF_GZ" -nt "$VCF_TBI" ]]; then
    tabix -p vcf "$VCF_GZ"
  fi
done

# Collapsed TSV with header and one line per variant across all samples
OUT="results/collapsed.tsv"
if [[ ! -f "$OUT" ]]; then
  printf "sample\tchrom\tpos\tref\talt\taf\n" > "$OUT"
fi
for samp in "${samples[@]}"; do
  VCF_GZ="results/${samp}.vcf.gz"
  if [[ -f "$VCF_GZ" ]]; then
    zcat "$VCF_GZ" |
      grep -v '^#' |
      while IFS=$'\t' read -r chrom pos id ref alt info rest; do
        # Extract allele frequency (AF) from INFO field, default to 0 if missing
        af=$(echo "$info" | tr ';' '\n' | awk -F '=' '$1 == "AF"{print $2}' | head -n1)
        [[ -z "$af" ]] && af=0
        printf "%s\t%s\t%s\t%s\t%s\t%.6f\n" "$samp" "$chrom" "$pos" "$ref" "$alt" "$af" >> "$OUT"
      done
  fi
done