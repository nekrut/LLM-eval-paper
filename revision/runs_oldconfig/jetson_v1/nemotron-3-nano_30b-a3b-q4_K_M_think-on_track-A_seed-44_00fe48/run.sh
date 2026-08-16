#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)

mkdir -p results

# If everything is already present, exit cleanly
all_done=true
for s in "${SAMPLES[@]}"; do
  for f in results/${s}.bam results/${s}.bam.bai results/${s}.vcf.gz.tbi; do
    if [ ! -f "$f" ]; then
      all_done=false
      break 2
    fi
  done
done
if [ "$all_done" = true ] && [ -f results/collapsed.tsv ]; then
  exit 0
fi

# Index reference once
if [ ! -f data/ref/chrM.fa.fai ]; then
  samtools faidx data/ref/chrM.fa
fi
if [ ! -f data/ref/chrM.fa.bwt ]; then
  bwa index data/ref/chrM.fa
fi

# Process each sample
for sample in "${SAMPLES[@]}"; do
  bam=results/${sample}.bam
  bai=results/${sample}.bam.bai
  vcf=results/${sample}.vcf
  vcz=results/${sample}.vcf.gz
  tbi=results/${sample}.vcf.gz.tbi

  # Skip if final TBI already exists
  if [ -f "$tbi" ]; then
    continue
  fi

  # Align if BAM missing
  if [ ! -f "$bam" ]; then
    bwa mem -t "$THREADS" -R "@RG\\tID:${sample}\\tSM:${sample}\\tLB:${sample}\\tPL:ILLUMINA" \
      "data/raw/${sample}_1.fq.gz" "data/raw/${sample}_2.fq.gz" |
      samtools sort -@ "$THREADS" -o "$bam"
  fi

  # Index if BAIT missing
  if [ ! -f "$bai" ]; then
    samtools index -@ "$THREADS" "$bam"
  fi

  # Variant calling if VCF missing
  if [ ! -f "$vcf" ]; then
    lofreq call-parallel --pp-threads 4 data/ref/chrM.fa "$bam" -o "$vcf"
  fi

  # Compress and index if needed
  if [ ! -f "$vcz" ]; then
    bgzip -c "$vcf" > "$vcz"
    tabix -p vcf "$vcz"
    rm -f "$vcf"
  fi
done

# Build collapsed.tsv if not present
if [ ! -f results/collapsed.tsv ]; then
  cat > results/collapsed.tsv <<'END_HEADER'
sample	chrom	pos	ref	alt	af
END_HEADER
  for sample in "${SAMPLES[@]}"; do
    bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "results/${sample}.vcf.gz" |
      awk -v s="${sample}" '{print s"\t"$0}' >> results/collapsed.tsv
  done
fi

exit 0