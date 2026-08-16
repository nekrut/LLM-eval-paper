#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)
REF=data/ref/chrM.fa
RAW=data/raw
OUTDIR=results

mkdir -p "$OUTDIR"

# ---- Reference indexing (once) -------------------------------------------------
if [[ ! -f "$REF.fai" ]]; then
  samtools faidx "$REF"
fi
if [[ ! -f "$REF.bwt" ]]; then
  bwa index "$REF"
fi

# Helper to decide if a target needs regeneration based on timestamps and existence
needs_update() {
  local tgt=$1; shift
  for src in "$@"; do
    if [[ ! -e "$tgt" || "$src" -nt "$tgt" ]]; then
      return 0   # true: update needed
    fi
  done
  return 1   # false: up‑to‑date
}

# ---- Per‑sample processing ------------------------------------------------------
for sample in "${SAMPLES[@]}"; do
  BAM="${OUTDIR}/${sample}.bam"
  BAI="${BAM}.bai"
  VCF="${OUTDIR}/${sample}.vcf.gz"
  VTBI="${VCF}.tbi"

  # ---------- Alignment + sorting -----------------------------------------------
  SAM_TMP=$(mktemp)
  if needs_update "$BAM" "$RAW/${sample}_1.fq.gz" "$RAW/${sample}_2.fq.gz" "$REF.bwt"; then
    bwa mem -t "$THREADS" \
      -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
      "$REF" \
      "$RAW/${sample}_1.fq.gz" "$RAW/${sample}_2.fq.gz" |
    samtools sort -@ "$THREADS" -o "$BAM"
    rm "$SAM_TMP"
  fi

  # ---------- BAM indexing ------------------------------------------------------
  if needs_update "$BAI" "$BAM"; then
    samtools index -@ "$THREADS" "$BAM"
  fi

  # ---------- Variant calling with lofreq ----------------------------------------
  VCF_UNCOMP="${OUTDIR}/${sample}.vcf"
  if needs_update "$VCF_UNCOMP" "$BAM" "$REF.bwt"; then
    lofreq call-parallel \
      --pp-threads "$THREADS" \
      -f "$REF" -o "$VCF_UNCOMP" "$BAM"
  fi

  # ---------- Compress & index VCF -----------------------------------------------
  if needs_update "$VTBI" "$VCF_UNCOMP"; then
    bgzip -c "$VCF_UNCOMP" >| "$VCF"
    tabix -p vcf "$VCF"
    rm "$VCF_UNCOMP"
  fi
done

# ---- Collapse step --------------------------------------------------------------
COLLAPSED="${OUTDIR}/collapsed.tsv"
if needs_update "$COLLAPSED" "${OUTDIR}/*.vcf.gz"; then
  {
    echo -e "sample\tchrom\tpos\tref\talt\taf"
    for sample in "${SAMPLES[@]}"; do
      bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' \
        "${OUTDIR}/${sample}.vcf.gz" | while IFS=$'\t' read -r chrom pos ref alt af; do
          echo -e "${sample}\t${chrom}\t${pos}\t${ref}\t${alt}\t${af}"
        done
    done
  } >| "$COLLAPSED"
fi

# Script ends successfully (no extra output)