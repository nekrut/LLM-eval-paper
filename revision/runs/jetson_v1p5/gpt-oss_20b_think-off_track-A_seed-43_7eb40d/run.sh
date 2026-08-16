#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

mkdir -p results

# Index reference if not already indexed
if [ ! -f data/ref/chrM.fa.bwt ]; then
  bwa index data/ref/chrM.fa
fi
if [ ! -f data/ref/chrM.fa.fai ]; then
  samtools faidx data/ref/chrM.fa
fi

for sample in "${SAMPLES[@]}"; do
  bam=results/${sample}.bam
  if [ ! -f "$bam" ]; then
    bwa mem -t $THREADS -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
      data/ref/chrM.fa data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz | \
      samtools sort -@ $THREADS -o "$bam" -
    samtools index -@ $THREADS "$bam"
  fi

  vcf_gz=results/${sample}.vcf.gz
  if [ ! -f "$vcf_gz" ]; then
    lofreq call-parallel --pp-threads $THREADS -f data/ref/chrM.fa -o results/${sample}.vcf "$bam"
    bcftools view -Oz -o "$vcf_gz" results/${sample}.vcf
    tabix -p vcf "$vcf_gz"
    rm results/${sample}.vcf
  else
    tbi=${vcf_gz}.tbi
    if [ ! -f "$tbi" ]; then
      tabix -p vcf "$vcf_gz"
    fi
  fi
done

collapsed=results/collapsed.tsv
if [ ! -f "$collapsed" ]; then
  printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed"
  for sample in "${SAMPLES[@]}"; do
    vcf_gz=results/${sample}.vcf.gz
    bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "$vcf_gz" | \
      awk -v s="$sample" 'BEGIN{OFS="\t"}{print s,$0}' >> "$collapsed"
  done
fi

exit 0