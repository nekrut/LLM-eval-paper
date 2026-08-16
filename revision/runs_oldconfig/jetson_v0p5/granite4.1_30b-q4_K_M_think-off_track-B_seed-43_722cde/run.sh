#!/usr/bin/env bash
set -euo pipefail

# Ensure reference is indexed once
REF=data/ref/chrM.fa
if [[ ! -f "${REF}.fai" ]]; then
  samtools faidx "$REF"
fi

THREADS=4
OUTDIR=results
mkdir -p "$OUTDIR"

SAMPLES=( M117-bl M117-ch M117C1-bl M117C1-ch )

# Process each sample if its VCF is not already present (idempotent)
for S in "${SAMPLES[@]}"; do
  BAM="${OUTDIR}/${S}.bam"
  VCF_GZ="${OUTDIR}/${S}.vcf.gz"

  # Skip if final VCF exists and appears complete
  if [[ -s "$VCF_GZ" && -s "${VCF_GZ}.tbi" ]]; then
    continue
  fi

  R1=data/raw/${S}_1.fq.gz
  R2=data/raw/${S}_2.fq.gz
  PREFIX="${OUTDIR}/${S}"

  # BWA alignment (paired-end)
  bwa mem -t "$THREADS" "$REF" "$R1" "$R2" > "${PREFIX}.sam"

  # Convert to BAM, sort, index
  samtools view -Sb "${PREFIX}.sam" \
    | samtools sort -@ "$THREADS" -o "$BAM" -
  samtools index "$BAM"

  # LoFreq variant calling (indel realignment + SNP/indel VCF)
  lofreq indelrealign -f "$REF" -i "$BAM"
  lofreq call -f "$REF" -o "${PREFIX}.unfiltered.vcf" -p "$THREADS" -t "$BAM"

  # Keep only PASS variants, bgzip and tabix‑index
  bcftools view -Ov -i 'FILTER="PASS"' "${PREFIX}.unfiltered.vcf" \
    | bgzip > "$VCF_GZ"
  rm -f "${PREFIX}.unfiltered.vcf"
  tabix -p vcf "$VCF_GZ"

  # Clean up intermediate files
  rm -f "${PREFIX}.sam"
done

# Collapse all per‑sample VCFs into a single TSV with header
COLLAPSED="${OUTDIR}/collapsed.tsv"
if [[ ! -s "$COLLAPSED" ]]; then
  {
    echo "sample\tchrom\tpos\tref\talt\taf"
    for S in "${SAMPLES[@]}"; do
      VCF_GZ="${OUTDIR}/${S}.vcf.gz"
      # Extract sample, position, ref/alt and allele fraction (AO/DP)
      bcftools query -f '%CHROM\t%POS\t%REF\t%ALT[\t%AF={AO}/({DP}+0.0)]\n' "$VCF_GZ" \
        | while IFS=$'\t' read -r chrom pos ref alt af; do
            echo "${S}\t${chrom}\t${pos}\t${ref}\t${alt}\t${af}"
          done
    done
  } > "$COLLAPSED"
fi

# End of script