#!/usr/bin/env bash
set -euo pipefail

THREADS=4
RESULTS="results"
RAW="data/raw"
REF_DIR="data/ref"
REF="${REF_DIR}/chrM.fa"

mkdir -p "$RESULTS"

EXPECTED=("$RESULTS/M117-bl.bam" "$RESULTS/M117-bl.bam.bai" "$RESULTS/M117-bl.vcf.gz" "$RESULTS/M117-bl.vcf.gz.tbi"
"$RESULTS/M117-ch.bam" "$RESULTS/M117-ch.bam.bai" "$RESULTS/M117-ch.vcf.gz" "$RESULTS/M117-ch.vcf.gz.tbi"
"$RESULTS/M117C1-bl.bam" "$RESULTS/M117C1-bl.bam.bai" "$RESULTS/M117C1-bl.vcf.gz" "$RESULTS/M117C1-bl.vcf.gz.tbi"
"$RESULTS/M117C1-ch.bam" "$RESULTS/M117C1-ch.bam.bai" "$RESULTS/M117C1-ch.vcf.gz" "$RESULTS/M117C1-ch.vcf.gz.tbi"
"$RESULTS/collapsed.tsv")
missing=0
for f in "${EXPECTED[@]}"; do
  if [[ ! -f "$f" ]]; then
    missing=1
    break
  fi
done
if (( missing == 0 )); then
  exit 0
fi

if [[ ! -f "${REF}.amb" ]]; then
  bwa index "$REF"
fi

samples=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

for sample in "${samples[@]}"; do
  r1="${RAW}/${sample}_1.fq.gz"
  r2="${RAW}/${sample}_2.fq.gz"
  bam_raw="${RESULTS}/${sample}.bam"
  bam_sorted="${RESULTS}/${sample}.sorted.bam"

  bwa mem -t "$THREADS" "${REF}" "$r1" "$r2" |
    samtools view -@ "$THREADS" -b - > "$bam_raw"

  samtools sort -@ "$THREADS" -o "$bam_sorted" "$bam_raw"
  samtools index "$bam_sorted"

  bcftools mpileup -f "$REF" -Ou -d 1000 -r chrM "${bam_sorted}" |
    bcftools call -mv -Oz -o "${RESULTS}/${sample}.vcf.gz"

  tabix -p vcf "${RESULTS}/${sample}.vcf.gz"
done

collapsed="${RESULTS}/collapsed.tsv"
printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed"

for sample in "${samples[@]}"; do
  vcf_file="${RESULTS}/${sample}.vcf.gz"
  bcftools query -r chrM -f '%CHROM\t%POS0\t%REF\t%ALT[\t%AF]\n' "$vcf_file" |
    while IFS=$'\t' read -r chrom pos ref alt af; do
      printf '%s\t%s\t%d\t%s\t%s\t%s\n' "$sample" "$chrom" "$pos" "$ref" "$alt" "$af" >> "$collapsed"
    done
done