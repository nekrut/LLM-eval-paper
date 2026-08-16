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

# List of sample prefixes (R1 and R2 files are present)
samples=(M117-bl M117-ch M117C1-bl M117C1-ch)

for samp in "${samples[@]}"; do
  # Define file paths
  fq1="data/raw/${samp}_1.fq.gz"
  fq2="data/raw/${samp}_2.fq.gz"
  bam="results/${samp}.bam"
  vcf_gz="results/${samp}.vcf.gz"

  # -------------------------------------------------
  # 1. Alignment with BWA MEM (paired-end)
  # -------------------------------------------------
  if [[ -f "$bam" && -f "${bam}.bai" ]]; then
    # Skip if BAM and index already exist
    :
  else
    bwa mem -t 4 "$REF" "$fq1" "$fq2" \
      | samtools view -bS -@ 4 - > "$bam"
    samtools sort -@ 4 "$bam" -o "$bam".sorted
    mv "$bam"{.sorted,}
    samtools index -@ 4 "$bam"
  fi

  # -------------------------------------------------
  # 2. Variant calling with LoFreq STAR (indel‑aware)
  # -------------------------------------------------
  if [[ -f "$vcf_gz" && -f "${vcf_gz}.tbi" ]]; then
    # Skip if VCF and index already exist
    :
  else
    lofreq call -f "$REF" -o "$vcf_gz" -p 4 --indel-mode star "$bam"
    bcftools index -t "$vcf_gz"
  fi
done

# -------------------------------------------------
# 3. Collapse VCFs into a single TSV (sample, chrom, pos, ref, alt, af)
# -------------------------------------------------
collapsed="results/collapsed.tsv"
if [[ -s "$collapsed" ]]; then
  # If file exists and is non‑empty, assume it's up‑to‑date; exit successfully.
  exit 0
else
  {
    echo "sample	chrom	pos	ref	alt	af"
    for samp in "${samples[@]}"; do
      vcf="results/${samp}.vcf.gz"
      bcftools view -H "$vcf" | while IFS=$'\t' read -r chrom pos id ref alt info rest; do
        # Extract allele frequency (AF) from INFO field
        af=$(echo "$info" | tr ';' '\n' | grep '^AF=' | cut -d= -f2)
        # Some records may have multiple alternate alleles; handle each ALT separately.
        IFS=',' read -ra alts <<<"$alt"
        for a in "${alts[@]}"; do
          echo "\"${samp}\"	\"$chrom\"	\"$pos\"	\"$ref\"	\"$a\"	\"${af:-0}\""
        done
      done
    done
  } > "$collapsed"
fi