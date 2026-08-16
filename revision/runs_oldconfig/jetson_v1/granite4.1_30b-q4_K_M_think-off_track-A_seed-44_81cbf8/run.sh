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
  local tgt="$1"
  shift
  for src in "$@"; do
    if [[ ! -e "$tgt" || "$src" -nt "$tgt" ]]; then
      return 0   # true: update needed
    fi
  done
  return 1   # false: up‑to‑date
}

# ---- Per‑sample processing ------------------------------------------------------
for sample in "${SAMPLES[@]}"; do
  FASTQ1="${RAW}/${sample}_1.fq.gz"
  FASTQ2="${RAW}/${sample}_2.fq.gz"

  BAM="${OUTDIR}/${sample}.bam"
  BAI="${OUTDIR}/${sample}.bam.bai"
  VCF="${OUTDIR}/${sample}.vcf.gz"
  VTBI="${OUTDIR}/${sample}.vcf.gz.tbi"
  VCFUN=${VCF%.gz}

  # ---------- Alignment & sorting -----------------------------------------------
  if needs_update "$BAM" "$FASTQ1" "$FASTQ2" "$REF.bwt"; then
    bwa mem -t "$THREADS" \
      -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
      "$REF" "$FASTQ1" "$FASTQ2" |
    samtools sort -@ "$THREADS" -o "$BAM"
  fi

  # ---------- BAM indexing ------------------------------------------------------
  if needs_update "$BAI" "$BAM"; then
    samtools index -@ "$THREADS" "$BAM"
  fi

  # ---------- Variant calling with lofreq ----------------------------------------
  if needs_update "$VCFUN" "$BAM" "$REF.bwt"; then
    lofreq call-parallel \
      --pp-threads "$THREADS" \
      -f "$REF" -o "$VCFUN" "$BAM"
  fi

  # ---------- Compress & index VCF -----------------------------------------------
  if needs_update "$VTBI" "$VCFUN"; then
    bgzip -c "$VCFUN" > "$VCF"
    rm "$VCFUN"
    tabix -p vcf "$VCF"
  fi
done

# ---- Collapse step --------------------------------------------------------------
COLLAPSED="${OUTDIR}/collapsed.tsv"
if needs_update "$COLLAPSED" "${OUTDIR}"/*.vcf.gz; then
  {
    echo -e "sample\tchrom\tpos\tref\talt\taf"
    for sample in "${SAMPLES[@]}"; do
      bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' \
        "${OUTDIR}/${sample}.vcf.gz" | while read -r line; do
          echo -e "${sample}\t${line}"
        done
    done
  } > "$COLLAPSED"
fi

# Script ends successfully (no extra output)