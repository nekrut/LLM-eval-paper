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
  # Define output file names
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
    samtools view -Sb - > "${BAM}.tmp"

  # Sort BAM and index it
  samtools sort -@ 4 -o "$BAM" "${BAM}.tmp"
  rm "${BAM}.tmp"
  samtools index "$BAM"

  # Variant calling with LoFreq Star
  lofreq star --call-indels --fasta-d "$REF" -s "$REF" -o "$VCF_GZ" "$BAM"

  # Tabix index the VCF
  tabix -p vcf "$VCF_GZ"
done

# Collapse variants into a single TSV with header
OUT_TSV="results/collapsed.tsv"
if [[ ! -f "$OUT_TSV" ]]; then
  {
    echo "sample\tchrom\tpos\tref\talt\taf"
    for samp in "${samples[@]}"; do
      VCF_GZ="results/${samp}.vcf.gz"
      # Extract sample-specific fields: CHROM, POS, REF, ALT, AF (FORMAT/FT)
      zgrep -h "^#" "$VCF_GZ" | grep -v "##FORMAT=<ID=FT"   # header without FT line
      zcat "$VCF_GZ" | \
        awk -F'\t' '
          $1 ~ /^#/ { next }
          {
            chrom=$1; pos=$2; ref=$4; alt=$5;
            split($9, ainfo, ":");  # sample format fields
            af=0;
            for (i in ainfo) {
              if (ainfo[i] == "FT") {
                split(ainfo[i+1], ftvals, ",");
                for (j in ftvals) {
                  if (ftvals[j] ~ /^A$/) { gsub(/^A=/, "", ftvals[j]); af=ftvals[j]; break }
                }
              }
            }
            printf "%s\t%s\t%d\t%s\t%s\t%.6f\n", "'"$samp"'", chrom, pos, ref, alt, af
          }' "$VCF_GZ"
    done
  } > "$OUT_TSV"
fi