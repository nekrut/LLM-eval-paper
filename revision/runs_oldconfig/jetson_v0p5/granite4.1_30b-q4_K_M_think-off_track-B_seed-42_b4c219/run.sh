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

SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)

# Process each sample if its VCF is not already present (idempotent)
for S in "${SAMPLES[@]}"; do
  VCF="${OUTDIR}/${S}.vcf.gz"
  if [[ -f "$VCF" ]]; then
    continue
  fi

  # Mapping with BWA MEM
  bwa mem -t "$THREADS" "$REF" "data/raw/${S}_1.fq.gz" "data/raw/${S}_2.fq.gz" \
    | samtools view -bS - > "${OUTDIR}/${S}.sam.bam"

  # Sort and index BAM
  samtools sort -@ "$THREADS" -o "${OUTDIR}/${S}.bam" "${OUTDIR}/${S}.sam.bam"
  rm "${OUTDIR}/${S}.sam.bam"
  samtools index -@ "$THREADS" "${OUTDIR}/${S}.bam"

  # Variant calling with LoFreq
  lofreq indelqual -f "$REF" -b "${OUTDIR}/${S}.bam" | \
    lofreq call -f "$REF" -b "${OUTDIR}/${S}.bam" > "${OUTDIR}/${S}.vcf"

  # Compress and index VCF
  bgzip -c "${OUTDIR}/${S}.vcf" > "$VCF"
  rm "${OUTDIR}/${S}.vcf"
  tabix -p vcf "$VCF"
done

# Collapse all per‑sample VCFs into a single TSV with header
COLLAPSED="${OUTDIR}/collapsed.tsv"
if [[ ! -f "$COLLAPSED" ]]; then
  {
    echo "sample\tchrom\tpos\tref\talt\taf"
    for S in "${SAMPLES[@]}"; do
      VCFGZ="${OUTDIR}/${S}.vcf.gz"
      tabix "$VCFGZ" | \
        bcftools query -f '%CHROM\t%POS\t%REF\t%ALT[0]\t%AF\n' "$VCFGZ" |
        awk -v sample="$S" '{print sample "\t" $0}'
    done
  } > "$COLLAPSED"
fi

exit 0