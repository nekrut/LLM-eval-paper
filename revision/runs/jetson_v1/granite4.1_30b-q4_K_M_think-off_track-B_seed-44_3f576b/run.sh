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

# Define sample list and input files
samples=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
for s in "${samples[@]}"; do
  R1="data/raw/${s}_1.fq.gz"
  R2="data/raw/${s}_2.fq.gz"
  OUT_PREFIX="results/${s}"

  # Skip if final VCF is already present (idempotent)
  if [[ -f "${OUT_PREFIX}.vcf.gz" && -f "${OUT_PREFIX}.vcf.gz.tbi" ]]; then
    continue
  fi

  # Alignment with BWA MEM to chrM
  bwa mem -t 4 "$REF" "$R1" "$R2" > "${OUT_PREFIX}.sam"

  # Convert SAM -> BAM, sort, index
  samtools view -Sb "${OUT_PREFIX}.sam" | \
    samtools sort -o "${OUT_PREFIX}.bam"
  rm "${OUT_PREFIX}.sam"
  samtools index "${OUT_PREFIX}.bam"

  # Variant calling with LoFreq Star
  lofreq star --call-indels --fasta "$REF" \
    -o "${OUT_PREFIX}.vcf" "${OUT_PREFIX}.bam"

  # Compress VCF and tabix-index it
  bgzip -c "${OUT_PREFIX}.vcf" > "${OUT_PREFIX}.vcf.gz"
  rm "${OUT_PREFIX}.vcf"
  tabix -p vcf "${OUT_PREFIX}.vcf.gz"
done

# Collapse per‑sample VCFs into a single TSV with header
> results/collapsed.tsv
echo -e "sample\tchrom\tpos\tref\talt\taf" >> results/collapsed.tsv
for s in "${samples[@]}"; do
  vcf="${s}.vcf.gz"
  if [[ -f "results/${vcf}" ]]; then
    zcat "results/${vcf}" | \
      grep -v '^#' | \
      awk -F'\t' '{print "'"${s}"'" \t \$1 \t \$2 \t \$3 \t \$4 \t '"\$((5+1))"''}' | \
      sed 's/AD=//g' | \
      awk -F',' '{ sum=0; n=0; for(i=1;i<=NF;i++) { split($i,a,"|"); depth=a[1]+(a[2]!= ""); sum+=depth; n++; } if(sum==0) af="0"; else af=sum/2; print $0 "\t" af }' | \
      cut -f1-6 >> results/collapsed.tsv
  fi
done