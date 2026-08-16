#!/usr/bin/env bash
set -euo pipefail

THREADS=4
RAWDIR="data/raw"
OUTDIR="results"
REFDIR="${OUTDIR}/ref"
REF="${REFDIR}/chrM.fa"

mkdir -p "$OUTDIR" "$REFDIR"

SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)

# Stage and index reference under results/ (keep data/ untouched)
if [[ ! -s "$REF" ]]; then
  cp data/ref/chrM.fa "$REF"
fi
if [[ ! -s "${REF}.bwt" ]]; then
  bwa index "$REF"
fi
if [[ ! -s "${REF}.fai" ]]; then
  samtools faidx "$REF"
fi

for sample in "${SAMPLES[@]}"; do
  R1="${RAWDIR}/${sample}_1.fq.gz"
  R2="${RAWDIR}/${sample}_2.fq.gz"
  BAM="${OUTDIR}/${sample}.bam"
  BAI="${OUTDIR}/${sample}.bam.bai"
  VCF="${OUTDIR}/${sample}.vcf.gz"
  TBI="${OUTDIR}/${sample}.vcf.gz.tbi"

  if [[ ! -s "$BAM" || ! -s "$BAI" ]]; then
    bwa mem -t "$THREADS" \
      -R "@RG\tID:${sample}\tSM:${sample}\tPL:ILLUMINA" \
      "$REF" "$R1" "$R2" \
      | samtools sort -@ "$THREADS" -o "${BAM}.tmp" -
    mv "${BAM}.tmp" "$BAM"
    samtools index "$BAM"
  fi

  if [[ ! -s "$VCF" || ! -s "$TBI" ]]; then
    IQBAM="${OUTDIR}/${sample}.indelqual.bam"
    lofreq indelqual --dindel -f "$REF" -o "$IQBAM" "$BAM"
    samtools index "$IQBAM"
    lofreq call-parallel --pp-threads "$THREADS" -f "$REF" -o "${OUTDIR}/${sample}.vcf" "$IQBAM"
    bgzip -f "${OUTDIR}/${sample}.vcf"
    tabix -f -p vcf "$VCF"
    rm -f "$IQBAM" "${IQBAM}.bai"
  fi
done

COLLAPSED="${OUTDIR}/collapsed.tsv"
TMP_COLLAPSED="${COLLAPSED}.tmp"
{
  printf 'sample\tchrom\tpos\tref\talt\taf\n'
  for sample in "${SAMPLES[@]}"; do
    VCF="${OUTDIR}/${sample}.vcf.gz"
    bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "$VCF" \
      | awk -v s="$sample" 'BEGIN{OFS="\t"}{print s,$1,$2,$3,$4,$5}'
  done
} > "$TMP_COLLAPSED"
mv "$TMP_COLLAPSED" "$COLLAPSED"