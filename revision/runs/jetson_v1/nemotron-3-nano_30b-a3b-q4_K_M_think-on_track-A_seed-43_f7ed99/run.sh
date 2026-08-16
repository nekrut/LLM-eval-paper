#!/usr/bin/env bash
set -euo pipefail
THREADS=4
samples=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
mkdir -p results

# Index reference if needed
if [ ! -f data/ref/chrM.fa.fai ]; then
  samtools faidx data/ref/chrM.fa
fi
if [ ! -f data/ref/chrM.fa.amb ]; then
  bwa index data/ref/chrM.fa
fi

# Process each sample
for sample in "${samples[@]}"; do
  # Align and sort if BAM does not exist
  if [ ! -f results/${sample}.bam ]; then
    bwa mem -t $THREADS \
      -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
      data/ref/chrM.fa \
      data/raw/${sample}_1.fq.gz \
      data/raw/${sample}_2.fq.gz |
      samtools sort -@ $THREADS -o results/${sample}.bam
  fi

  # Index BAM if needed
  if [ ! -f results/${sample}.bam.bai ]; then
    samtools index -@ $THREADS results/${sample}.bam
  fi

  # Variant calling with lofreq if final TBI is missing
  if [ ! -f results/${sample}.vcf.gz.tbi ]; then
    lofreq call-parallel --pp-threads 4 -f data/ref/chrM.fa results/${sample}.bam -o results/${sample}.vcf
    bgzip -c results/${sample}.vcf > results/${sample}.vcf.gz
    tabix -p vcf results/${sample}.vcf.gz
    rm results/${sample}.vcf
  fi
done

# Rebuild collapsed.tsv if any VCF is newer than it
need_rebuild=0
if [ ! -f results/collapsed.tsv ]; then
  need_rebuild=1
else
  for s in "${samples[@]}"; do
    vcf="results/${s}.vcf.gz"
    if [ -f "$vcf" ] && [ "$(stat -c %Y "$vcf")" -nt results/collapsed.tsv ]; then
      need_rebuild=1
      break
    fi
  done
fi

if [ $need_rebuild -eq 1 ]; then
  {
    echo -e "sample\tchrom\tpos\tref\talt\taf"
    for s in "${samples[@]}"; do
      bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' results/${s}.vcf.gz |
        awk -v sample="${s}" '{print sample"\t"$0}'
    done
  } > results/collapsed.tsv
fi