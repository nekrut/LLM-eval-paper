#!/usr/bin/env bash
set -euo pipefail

THREADS=4
REF=data/ref/chrM.fa
RESULTS=results
RAW=data/raw

mkdir -p "$RESULTS"

samples=(M117-bl M117-ch M117C1-bl M117C1-ch)

# Exit if all outputs already exist
all_present=true
for s in "${samples[@]}"; do
  for ext in bam bai vcf.gz tbi; do
    [[ -f "$RESULTS/${s}.${ext}" ]] || { all_present=false; break 2; }
  done
done

if $all_present && [[ -f "$RESULTS/collapsed.tsv" ]]; then exit 0; fi

# Index reference if needed
[[ -f "${REF}.bwt" ]] || bwa index "$REF"
[[ -f "${REF}.fai" ]] || samtools faidx "$REF"

for s in "${samples[@]}"; do
  bam="$RESULTS/${s}.bam"
  bai="$RESULTS/${s}.bai"
  vcf="$RESULTS/${s}.vcf.gz"
  tbi="$RESULTS/${s}.vcf.gz.tbi"

  # Map reads if BAM missing
  if [[ ! -f "$bam" ]]; then
    read1="$RAW/${s}_1.fq.gz"
    read2="$RAW/${s}_2.fq.gz"
    bwa mem -t $THREADS "$REF" "$read1" "$read2" | samtools sort -@ $THREADS -o "$bam"
  fi

  # Index BAM if missing
  [[ -f "$bai" ]] || samtools index "$bam"

  # Variant calling if VCF.gz missing
  if [[ ! -f "$vcf" ]]; then
    tmp_vcf="${s}.tmp.vcf"
    lofreq call -f "$REF" -b "$bam" -o "$tmp_vcf"
    bcftools view -O z -o "$vcf" "$tmp_vcf"
    rm "$tmp_vcf"
  fi

  # Index VCF if missing
  [[ -f "$tbi" ]] || tabix -p vcf "$vcf"
done

# Create collapsed.tsv if missing
if [[ ! -f "$RESULTS/collapsed.tsv" ]]; then
  echo -e "sample\tchrom\tpos\tref\talt\taf" > "$RESULTS/collapsed.tsv"
  for s in "${samples[@]}"; do
    vcf="$RESULTS/${s}.vcf.gz"
    zcat "$vcf" | awk -F'\t' 'BEGIN{OFS="\t"} NR>1 && $1 !~ /^#/ {
      split($8,a,";"); af=""; for(i in a){if(a[i] ~ /^AF=/){af=substr(a[i],4);break}}
      print "'"$s"'", $1, $2, $4, $5, af
    }' >> "$RESULTS/collapsed.tsv"
  done
fi

exit 0