#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
REF="data/ref/chrM.fa"
RESULTS_DIR="results"

# Check if all expected outputs already exist
all_done=true
for sample in "${SAMPLES[@]}"; do
  [[ -f "$RESULTS_DIR/${sample}.bam" ]] || { all_done=false; break; }
  [[ -f "$RESULTS_DIR/${sample}.bam.bai" ]] || { all_done=false; break; }
  [[ -f "$RESULTS_DIR/${sample}.vcf.gz" ]] || { all_done=false; break; }
  [[ -f "$RESULTS_DIR/${sample}.vcf.gz.tbi" ]] || { all_done=false; break; }
done
[[ -f "$RESULTS_DIR/collapsed.tsv" ]] || all_done=false

if $all_done; then
  exit 0
fi

mkdir -p "$RESULTS_DIR"

# Reference indexing (BWA)
if [[ ! -f "${REF}.bwt" ]]; then
  bwa index "$REF"
fi

# Reference indexing (samtools faidx)
if [[ ! -f "${REF}.fa.fai" ]]; then
  samtools faidx "$REF"
fi

for sample in "${SAMPLES[@]}"; do
  BAM="$RESULTS_DIR/${sample}.bam"
  BAI="${BAM}.bai"
  VCF_GZ="$RESULTS_DIR/${sample}.vcf.gz"

  # Alignment and sorting if BAM missing
  if [[ ! -f "$BAM" ]]; then
    bwa mem -t "$THREADS" \
      -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
      "$REF" "data/raw/${sample}_1.fq.gz" "data/raw/${sample}_2.fq.gz" | \
      samtools sort -@ "$THREADS" -o "$BAM" -
  fi

  # BAM index if missing
  if [[ ! -f "$BAI" ]]; then
    samtools index -@ "$THREADS" "$BAM"
  fi

  # Variant calling and compression if VCF.gz missing
  if [[ ! -f "$VCF_GZ" ]]; then
    VCF_TMP="$RESULTS_DIR/${sample}.vcf"
    lofreq call-parallel --pp-threads "$THREADS" -f "$REF" -o "$VCF_TMP" "$BAM"
    bcftools view -Oz -o "$VCF_GZ" "$VCF_TMP"
    rm -f "$VCF_TMP"
    tabix -p vcf "$VCF_GZ"
  fi
done

# Create collapsed.tsv
COLLAPSED="$RESULTS_DIR/collapsed.tsv"
printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$COLLAPSED"
for sample in "${SAMPLES[@]}"; do
  bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "$RESULTS_DIR/${sample}.vcf.gz" | \
    awk -v s="$sample" 'BEGIN{OFS="\t"}{print s,$0}' >> "$COLLAPSED"
done

exit 0