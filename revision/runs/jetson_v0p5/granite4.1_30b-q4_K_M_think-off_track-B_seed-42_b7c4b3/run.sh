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
if [[ ! -f "$REF".bwt || ! -f "$REF".pac || ! -f "$REF".ann || ! -f "$REF".sa ]]; then
  bwa index "$REF"
fi

# List of sample prefixes (R1 and R2 files are _1.fq.gz and _2.fq.gz)
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

  # FastQC (optional quality check, output goes to results/ but not required for downstream)
  fastqc "data/raw/${samp}_1.fq.gz" "data/raw/${samp}_2.fq.gz" -o results/

  # Alignment with BWA MEM (paired-end)
  bwa mem "$REF" "data/raw/${samp}_1.fq.gz" "data/raw/${samp}_2.fq.gz" > "${samp}.sam"

  # Convert SAM to BAM, sort, and index
  samtools view -Sb "${samp}.sam" | \
    samtools sort -o "$BAM"
  rm "${samp}.sam"
  samtools index "$BAM"

  # Variant calling with LoFreq STAR (indel-aware)
  lofreq star --call-indels -f "$REF" -o "${samp}_lofreq.vcf" "$BAM"

  # Filter to PASS, bgzip, tabix-index
  bcftools view -i 'FILTER="PASS"' "${samp}_lofreq.vcf" \
    | bcftools norm -m -both - > "${samp}_filtered.vcf"
  bcftools index "${samp}_filtered.vcf"

  # Compress and index the final VCF
  bgzip -c "${samp}_filtered.vcf" > "$VCF_GZ"
  tabix -p vcf "$VCF_GZ"

  # Clean up intermediate files
  rm "${samp}_lofreq.vcf" "${samp}_filtered.vcf" "${samp}_filtered.vcf.csi"

done

# Collapse per‑sample VCFs into a single TSV with header
(
  echo -e "sample\tchrom\tpos\tref\talt\taf"
  for samp in "${samples[@]}"; do
    VCF_GZ="results/${samp}.vcf.gz"
    if [[ -f "$VCF_GZ" ]]; then
      bcftools query -f '%CHROM\t%POS\t%REF\t%ALT[\t%AF]\n' "$VCF_GZ" | \
        awk -v samp="$samp" '{print samp "\t" $0}'
    fi
  done
) > "results/collapsed.tsv"

# End of script