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
  # Define input FASTQs
  R1="data/raw/${samp}_1.fq.gz"
  R2="data/raw/${samp}_2.fq.gz"
  
  # Output filenames
  BAM="results/${samp}.bam"
  BAI="${BAM}.bai"
  VCFGZ="results/${samp}.vcf.gz"
  VCFTBI="${VCFGZ}.tbi"

  # Skip if final VCF and its index already exist (idempotent)
  if [[ -f "$VCFGZ" && -f "$VCFTBI" ]]; then
    continue
  fi

  # --- Alignment with BWA ---
  # Unsorted BAM goes to a temporary file; sorted BAM is written directly.
  bwa mem -t 4 "$REF" "$R1" "$R2" \
    | samtools view -bS - > "${BAM}.unsorted"

  # Sort and index
  samtools sort -@ 4 -o "$BAM" "${BAM}.unsorted"
  rm -f "${BAM}.unsorted"
  samtools index -@ 4 "$BAM"

  # --- Variant calling with LoFreq ---
  lofreq call -f "$REF" -r chrM -t 4 -o "$VCFGZ" "$BAM"

  # Tabix index the VCF
  tabix -p vcf "$VCFGZ"
done

# --- Collapse variants into a single TSV ---
OUT_TSV="results/collapsed.tsv"
if [[ ! -f "$OUT_TSV" ]]; then
  {
    echo "sample	chrom	pos	ref	alt	af"
    for samp in "${samples[@]}"; do
      VCFGZ="results/${samp}.vcf.gz"
      # Extract sample-specific AF from INFO field (format: AD=xxx,DP=yyy,AF=zzz)
      # LoFreq emits AF as a float after the key "AF="
      zcat "$VCFGZ" \
        | awk -F'\t' '
          $1!="#" {
            split($7,info,";")
            for(i in info) {
              if(info[i] ~ /^AF=/) {
                af=substr(info[i],4)
                print "'"$samp"'	chrM	"$2"	"$3"	"$4"	"af
                next 2
              }
            }
          }' 
    done
  } > "$OUT_TSV"
fi