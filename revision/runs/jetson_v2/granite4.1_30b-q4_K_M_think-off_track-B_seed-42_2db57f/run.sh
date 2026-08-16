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
  R1="data/raw/${samp}_1.fq.gz"
  R2="data/raw/${samp}_2.fq.gz"
  OUT_PREFIX="results/${samp}"

  # Skip if final VCF already exists (idempotent)
  if [[ -f "${OUT_PREFIX}.vcf.gz" && -f "${OUT_PREFIX}.vcf.gz.tbi" ]]; then
    continue
  fi

  # Alignment with BWA MEM to chrM
  bwa mem -t 4 "$REF" "$R1" "$R2" > "${OUT_PREFIX}.sam"

  # Convert SAM -> BAM, sort, index
  samtools view -Sb "${OUT_PREFIX}.sam" | \
    samtools sort -o "${OUT_PREFIX}.bam"
  rm "${OUT_PREFIX}.sam"
  samtools index "${OUT_PREFIX}.bam"

  # Variant calling with LoFreq Star (indel-realign + variant call)
  lofreq star --ref "$REF" --call-indels \
               --in "${OUT_PREFIX}.bam" \
               --out "${OUT_PREFIX}.vcf" \
               -t 4

  # Compress VCF and index
  bgzip -c "${OUT_PREFIX}.vcf" > "${OUT_PREFIX}.vcf.gz"
  rm "${OUT_PREFIX}.vcf"
  tabix -p vcf "${OUT_PREFIX}.vcf.gz"

done

# Collapse per‑sample VCFs into a single TSV with header
> results/collapsed.tsv
echo -e "sample\tchrom\tpos\tref\talt\taf" >> results/collapsed.tsv

for samp in "${samples[@]}"; do
  VCF="results/${samp}.vcf.gz"
  # Extract INFO.FORMAT:AF (first alternate allele) and add sample column
  zcat "$VCF" | tail -n +2 | awk -F'\t' '
    $5!="'"'"'"{ 
      split($8,a,";"); 
      for(i in a){ if(a[i] ~ /^AF=/){ split(a[i],b,"="); print "'"$samp"'\\t'$1'\\t'$2'\\t'$3'\\t'$4'\\t'"$5"'" "\\tb"b[2]; next }}}' \
    >> results/collapsed.tsv
done