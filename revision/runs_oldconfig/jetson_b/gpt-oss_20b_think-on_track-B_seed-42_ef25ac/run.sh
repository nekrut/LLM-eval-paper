#!/usr/bin/env bash
set -euo pipefail

RAW=data/raw
REF=data/ref/chrM.fa
OUT=results
THREADS=4

# Ensure output directory exists
mkdir -p "$OUT"

# List of samples
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

# Check if all expected outputs already exist; exit if so
EXPECTED=(
  "${OUT}/M117-bl.bam" "${OUT}/M117-bl.bam.bai"
  "${OUT}/M117-ch.bam" "${OUT}/M117-ch.bam.bai"
  "${OUT}/M117C1-bl.bam" "${OUT}/M117C1-bl.bam.bai"
  "${OUT}/M117C1-ch.bam" "${OUT}/M117C1-ch.bam.bai"
  "${OUT}/M117-bl.vcf.gz" "${OUT}/M117-bl.vcf.gz.tbi"
  "${OUT}/M117-ch.vcf.gz" "${OUT}/M117-ch.vcf.gz.tbi"
  "${OUT}/M117C1-bl.vcf.gz" "${OUT}/M117C1-bl.vcf.gz.tbi"
  "${OUT}/M117C1-ch.vcf.gz" "${OUT}/M117C1-ch.vcf.gz.tbi"
  "${OUT}/collapsed.tsv"
)
all_present=true
for f in "${EXPECTED[@]}"; do
  if [ ! -f "$f" ]; then
    all_present=false
    break
  fi
done
if $all_present; then exit 0; fi

# Index reference if not already indexed
if [ ! -f "${REF}.bwt" ]; then
  bwa index "$REF"
fi

# Process each sample
for sample in "${SAMPLES[@]}"; do
  bam="${OUT}/${sample}.bam"
  vcf="${OUT}/${sample}.vcf.gz"

  # Map reads if BAM missing
  if [ ! -f "$bam" ]; then
    bwa mem -t "$THREADS" "$REF" \
      "${RAW}/${sample}_1.fq.gz" "${RAW}/${sample}_2.fq.gz" |
      samtools sort -@ "$THREADS" -o "$bam"
    samtools index "$bam"
  fi

  # Call variants if VCF missing
  if [ ! -f "$vcf" ]; then
    lofreq call -f "$REF" -o "${OUT}/${sample}.vcf" "$bam"
    bcftools view -O z -o "$vcf" "${OUT}/${sample}.vcf"
    rm "${OUT}/${sample}.vcf"
    tabix -p vcf "$vcf"
  fi
done

# Create collapsed table if missing
if [ ! -f "${OUT}/collapsed.tsv" ]; then
  printf "sample\tchrom\tpos\tref\talt\taf\n" > "${OUT}/collapsed.tsv"
  for sample in "${SAMPLES[@]}"; do
    vcf="${OUT}/${sample}.vcf.gz"
    if [ -f "$vcf" ]; then
      bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t[%AF]\n' "$vcf" |
        awk -v s="$sample" 'BEGIN{OFS="\t"} {print s, $0}' >> "${OUT}/collapsed.tsv"
    fi
  done
fi

exit 0