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

  # ---------- Mapping with BWA ----------
  # Run only if the sorted BAM does not exist
  if [[ ! -f "$bam" || ! -f "${bam}.bai" ]]; then
    bwa mem -t 4 "$REF" "$fq1" "$fq2" |
      samtools view -Sb - > "tmp_${samp}.sam"
    samtools sort -o "$bam" "tmp_${samp}.sam"
    rm "tmp_${samp}.sam"
    samtools index "$bam"
  fi

  # ---------- Variant calling with LoFreq ----------
  # Run only if the VCF does not exist
  if [[ ! -f "$vcf_gz" || ! -f "${vcf_gz}.tbi" ]]; then
    lofreq call -f "$REF" -o "$vcf_gz" --dindel -p 4 "$bam"
    bgzip -c "$vcf_gz" > "${vcf_gz}.gz"
    mv "${vcf_gz}.gz" "$vcf_gz"
    rm "$vcf_gz"
    tabix -p vcf "$vcf_gz"
  fi
done

# ---------- Collapsed TSV across all samples ----------
collapsed="results/collapsed.tsv"
if [[ ! -s "$collapsed" ]]; then
  # Header line
  echo -e "sample\tchrom\tpos\tref\talt\taf" > "$collapsed"
  for samp in "${samples[@]}"; do
    vcf_gz="results/${samp}.vcf.gz"
    # Extract relevant columns: sample, CHROM, POS, REF, ALT, AF (FORMAT/second sample)
    zcat "$vcf_gz" |
      awk -v samp="$samp" '
        $1 ~ /^#/ {next}
        { 
          split($8, af_arr, ";");
          for (i in af_arr) {
            if (af_arr[i] ~ /^AF=/) {
              gsub(/^AF=/, "", af_arr[i]);
              print samp "\t" $1 "\t" $2 "\t" $3 "\t" $4 "\t" af_arr[i];
            }
          }
        }' >> "$collapsed"
  done
fi

# Script completes successfully
exit 0