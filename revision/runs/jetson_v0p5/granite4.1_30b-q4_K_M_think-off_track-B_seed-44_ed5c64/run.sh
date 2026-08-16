#!/usr/bin/env bash
set -euo pipefail

# Ensure output directory exists
mkdir -p results

# Reference genome (already present in data/ref/)
REF="data/ref/chrM.fa"

# Index reference if not already indexed
if [[ ! -f "${REF}.fai" ]]; then
  samtools faidx "$REF"
fi
if [[ ! -f "${REF}.bwt" ]] || [[ ! -f "${REF}.pac" ]] || [[ ! -f "${REF}.ann" ]] || [[ ! -f "${REF}.sa" ]]; then
  bwa index "$REF"
fi

# List of sample prefixes (R1 and R2 files are _1.fq.gz and _2.fq.gz)
samples=(M117-bl M117-ch M117C1-bl M117C1-ch)

THREADS=4

for samp in "${samples[@]}"; do
  # Define file names
  fq1="data/raw/${samp}_1.fq.gz"
  fq2="data/raw/${samp}_2.fq.gz"
  bam="results/${samp}.bam"
  vcf_gz="results/${samp}.vcf.gz"

  # If VCF already exists, skip this sample (idempotent)
  if [[ -f "$vcf_gz" ]]; then
    continue
  fi

  # Mapping with BWA MEM
  bwa mem -t "$THREADS" "$REF" "$fq1" "$fq2" \
    | samtools view -bS - > "${bam%.bam}.tmp.bam"

  # Sort and index BAM
  samtools sort -@ "$THREADS" -o "$bam" "${bam%.bam}.tmp.bam"
  rm "${bam%.bam}.tmp.bam"
  samtools index "$bam"

  # Variant calling with LoFreq STAR
  lofreq star --threads "$THREADS" \
    --call-indels \
    --fasta "$REF" \
    --inpf1 "$fq1" --inpf2 "$fq2" \
    --outdir "results/${samp}_lofreq_tmp"

  # Convert LoFreq VCF to bgzipped and index
  vcf_in="results/${samp}_lofreq_tmp/${samp}.var.vcf"
  bcftools view -Oz -o "$vcf_gz" "$vcf_in"
  rm -rf "results/${samp}_lofreq_tmp"
  bcftools index "$vcf_gz"
done

# Collapse variants across all samples into a single TSV
out_tsv="results/collapsed.tsv"
if [[ ! -f "$out_tsv" ]]; then
  # Header line
  echo -e "sample\tchrom\tpos\tref\talt\taf" > "$out_tsv"

  for samp in "${samples[@]}"; do
    vcf_gz="results/${samp}.vcf.gz"
    if [[ -f "$vcf_gz" ]]; then
      # Extract sample, chrom, pos, ref, alt, AF; filter INFO.AF present and >0.05 (optional)
      bcftools query -f '%CHROM\t%POS\t%REF\t%ALT[0]\t%INFO(AF)\n' "$vcf_gz" \
        | awk -v samp="$samp" '{print samp "\t" $0}' >> "$out_tsv"
    fi
  done
fi