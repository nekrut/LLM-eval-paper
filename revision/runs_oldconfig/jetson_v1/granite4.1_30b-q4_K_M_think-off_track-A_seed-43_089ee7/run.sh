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

# Helper to skip a step if its output exists and is newer than all inputs
needs_update() {
  local out=$1; shift
  for f in "$@"; do
    if [[ ! -e "$out" || "$f" -nt "$out" ]]; then
      return 0   # needs update
    fi
  done
  return 1   # up‑to‑date
}

# ---- Per‑sample processing ------------------------------------------------------
for sample in "${SAMPLES[@]}"; do
  R1="${RAW}/${sample}_1.fq.gz"
  R2="${RAW}/${sample}_2.fq.gz"
  BAM="${OUTDIR}/${sample}.bam"
  BAI="${BAM}.bai"
  VCFU="${OUTDIR}/${sample}.vcf"
  VGZ="${OUTDIR}/${sample}.vcf.gz"
  VTBI="${VGZ}.tbi"

  # ---------- Alignment + sorting ----------
  if needs_update "$BAM" "$R1" "$R2" "$REF" "$REF.fai" "$REF.bwt"; then
    bwa mem -t "$THREADS" \
      -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
      "$REF" "$R1" "$R2" |
    samtools sort -@ "$THREADS" -o "$BAM"
  fi

  # ---------- BAM indexing ----------
  if needs_update "$BAI" "$BAM"; then
    samtools index -@ "$THREADS" "$BAM"
  fi

  # ---------- Variant calling with lofreq ----------
  if needs_update "$VCFU" "$BAM" "$REF" "$REF.fai"; then
    lofreq call-parallel --pp-threads "$THREADS" \
      -f "$REF" -o "$VCFU" "$BAM"
  fi

  # ---------- VCF compression & indexing ----------
  if needs_update "$VGZ" "$VCFU"; then
    bgzip -c "$VCFU" > "$VGZ"
    rm "$VCFU"
  fi
  if needs_update "$VTBI" "$VGZ"; then
    tabix -p vcf "$VGZ"
  fi

done

# ---- Collapse step -------------------------------------------------------------
COLLAPSED="${OUTDIR}/collapsed.tsv"
if needs_update "$COLLAPSED" "${SAMPLES[@]/%/.vcf.gz}"; then
  {
    echo -e "sample\tchrom\tpos\tref\talt\taf"
    for sample in "${SAMPLES[@]}"; do
      VGZ="${OUTDIR}/${sample}.vcf.gz"
      bcftools query -f '%SAMPLE\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "$VGZ" \
        | sed "s|^|${sample}\t|"
    done
  } > "$COLLAPSED"
fi

# Script ends successfully; no further output.