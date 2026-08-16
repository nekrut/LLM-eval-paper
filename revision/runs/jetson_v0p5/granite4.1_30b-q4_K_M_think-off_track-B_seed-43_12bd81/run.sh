#!/usr/bin/env bash
set -euo pipefail

# Ensure output directory exists
mkdir -p results

# Reference genome (already decompressed)
REF="data/ref/chrM.fa"

# Index reference if not present
if [[ ! -f "$REF".fai ]]; then
  samtools faidx "$REF"
fi
if [[ ! -f "$REF".bwt || ! -f "$REF".sa ]]; then
  bwa index "$REF"
fi

# List of sample prefixes (R1 and R2 files are present)
samples=(M117-bl M117-ch M117C1-bl M117C1-ch)

for samp in "${samples[@]}"; do
  # Define file names
  fq1="data/raw/${samp}_1.fq.gz"
  fq2="data/raw/${samp}_2.fq.gz"
  bam="results/${samp}.bam"
  vcf_gz="results/${samp}.vcf.gz"

  # Skip if final VCF already exists (idempotence)
  if [[ -f "$vcf_gz" && -f "${vcf_gz}.tbi" ]]; then
    continue
  fi

  # Mapping with BWA MEM
  bwa mem -t 4 "$REF" "$fq1" "$fq2" \
    | samtools view -Sb - > "$bam"

  # Sort and index BAM
  if [[ ! -f "$bam" ]]; then
    echo "Mapping failed for $samp" >&2
    exit 1
  fi
  samtools sort -@ 4 -o "$bam" -O bam "$bam"
  samtools index "$bam"

  # Variant calling with LoFreq STAR
  lofreq star --ref "$REF" --call-indels \
    --in "$bam" --out "${vcf_gz%.gz}" --write-vcf

  # Compress and tabix-index VCF
  bgzip -c "${vcf_gz%.gz}" > "$vcf_gz"
  rm -f "${vcf_gz%.gz}"
  tabix -p vcf "$vcf_gz"
done

# Collapse all per‑sample VCFs into a single TSV with header
collapsed="results/collapsed.tsv"
if [[ ! -f "$collapsed" ]]; then
  {
    echo "sample\tchrom\tpos\tref\talt\taf"
    for samp in "${samples[@]}"; do
      vcf_gz="results/${samp}.vcf.gz"
      if [[ -f "$vcf_gz" ]]; then
        zcat "$vcf_gz" \
          | awk 'NR==1 || ($1!="#" && $7 ~ /AF=/)' \
          | while IFS=$'\t' read -r chrom pos id ref alt info rest; do
              af=$(echo "$info" | perl -nle 'if (m/AF=([^;]+)/) { print $1 }')
              echo "${samp}\t${chrom}\t${pos}\t${ref}\t${alt}\t${af}"
            done
      fi
    done
  } > "$collapsed"
fi

# End of script