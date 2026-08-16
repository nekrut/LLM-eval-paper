#!/usr/bin/env bash
set -euo pipefail

# Ensure output directory exists
mkdir -p results

# Reference preparation (idempotent)
REF="data/ref/chrM.fa"
if [[ ! -f "${REF}.fai" ]]; then
  samtools faidx "$REF"
fi
if [[ ! -f "${REF}.bwt" ]]; then
  bwa index "$REF"
fi

# List of samples (paired-end files)
samples=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

THREADS=4

for sample in "${samples[@]}"; do
  R1="data/raw/${sample}_1.fq.gz"
  R2="data/raw/${sample}_2.fq.gz"
  OUT_PREFIX="results/${sample}"

  # Skip if final VCF is already present (idempotent)
  if [[ -f "${OUT_PREFIX}.vcf.gz" ]] && \
     [[ -f "${OUT_PREFIX}.vcf.gz.tbi" ]] && \
     [[ -f "${OUT_PREFIX}.bam" ]] && \
     [[ -f "${OUT_PREFIX}.bam.bai" ]]; then
    continue
  fi

  # Alignment with BWA MEM (paired-end)
  bwa mem -t "$THREADS" "$REF" "$R1" "$R2" > "${OUT_PREFIX}.sam"

  # Convert SAM to BAM, sort and index
  samtools view -bS "${OUT_PREFIX}.sam" \
    | samtools sort -@ "$THREADS" -o "${OUT_PREFIX}.bam"
  rm "${OUT_PREFIX}.sam"
  samtools index "${OUT_PREFIX}.bam"

  # Variant calling with LoFreq Star (indel realignment + variant calling)
  lofreq star --threads "$THREADS" \
    --ref "$REF" \
    --in "${OUT_PREFIX}.bam" \
    --out "${OUT_PREFIX}.vcf"

  # Compress VCF and index
  bgzip -c "${OUT_PREFIX}.vcf" > "${OUT_PREFIX}.vcf.gz"
  rm "${OUT_PREFIX}.vcf"
  tabix -p vcf "${OUT_PREFIX}.vcf.gz"
done

# Collapse variants into a single TSV with header
COLLAPSED="results/collapsed.tsv"
if [[ ! -f "$COLLAPSED" ]]; then
  printf "sample\tchrom\tpos\tref\talt\taf\n" > "$COLLAPSED"
fi
for sample in "${samples[@]}"; do
  VCF_GZ="results/${sample}.vcf.gz"
  # Extract INFO.AF (average allele frequency) if present, otherwise set to .0
  zcat "$VCF_GZ" \
    | awk -F'\t' '
        $1 != "#" {
          split($8, info, ";");
          af = ".";
          for (i in info) {
            if (info[i] ~ /^AF=/) {
              af = substr(info[i], 4);
              break;
            }
          }
          print "'"$sample"'\t"$1"\t"$2"\t"$3"\t"$4"\t"af
        }' >> "$COLLAPSED"
done

# End of script