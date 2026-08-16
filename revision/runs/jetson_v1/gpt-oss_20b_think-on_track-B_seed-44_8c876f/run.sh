#!/usr/bin/env bash
set -euo pipefail

THREADS=${THREADS:-4}
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

# Exit immediately if all expected outputs already exist
all_exists=true
for s in "${SAMPLES[@]}"; do
  for ext in bam bai vcf.gz tbi; do
    [[ -f results/${s}.${ext} ]] || { all_exists=false; break 2; }
  done
done
[[ $all_exists == true && -f results/collapsed.tsv ]] && exit 0

mkdir -p results

# Index reference if necessary
if [[ ! -f data/ref/chrM.fa.bwt ]]; then bwa index data/ref/chrM.fa; fi
if [[ ! -f data/ref/chrM.fa.fai ]]; then samtools faidx data/ref/chrM.fa; fi

for s in "${SAMPLES[@]}"; do
  # Map reads and create sorted BAM
  bwa mem -t "$THREADS" data/ref/chrM.fa \
    data/raw/${s}_1.fq.gz data/raw/${s}_2.fq.gz |
    samtools view -bS - | samtools sort -o results/${s}.bam

  # Index BAM
  samtools index results/${s}.bam

  # Call variants with lofreq
  lofreq call --no-default-filter -f data/ref/chrM.fa \
    -q 20 -Q 30 -o results/${s}.vcf.gz results/${s}.bam

  # Index VCF
  tabix -p vcf results/${s}.vcf.gz
done

# Create collapsed table
echo -e "sample\tchrom\tpos\tref\talt\taf" > results/collapsed.tsv
for s in "${SAMPLES[@]}"; do
  bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' \
    results/${s}.vcf.gz |
    awk -v samp="$s" '{print samp"\t"$0}' >> results/collapsed.tsv
done

exit 0