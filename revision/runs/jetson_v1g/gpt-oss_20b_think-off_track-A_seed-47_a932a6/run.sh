#!/usr/bin/env bash
set -euo pipefail

THREADS=4
samples=(M117-bl M117-ch M117C1-bl M117C1-ch)

mkdir -p results

# Reference indexing
if [ ! -f data/ref/chrM.fa.bwt ]; then
  samtools faidx data/ref/chrM.fa
  bwa index data/ref/chrM.fa
fi

for sample in "${samples[@]}"; do
  bam=results/${sample}.bam
  bai=results/${sample}.bam.bai
  vcf_gz=results/${sample}.vcf.gz
  vcf_tbi=results/${sample}.vcf.gz.tbi

  # Alignment and sorting
  if [ ! -f "$bam" ]; then
    bwa mem -t $THREADS \
      -R "@RG\tID:$sample\tSM:$sample\tLB:$sample\tPL:ILLUMINA" \
      data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz |
      samtools sort -@ $THREADS -o "$bam"
  fi

  # BAM indexing
  if [ ! -f "$bai" ]; then
    samtools index -@ $THREADS "$bam"
  fi

  # Variant calling
  if [ ! -f "$vcf_tbi" ]; then
    lofreq call-parallel --pp-threads $THREADS --verbose \
      --ref data/ref/chrM.fa --out results/${sample}.vcf \
      --sig --bonf "$bam"

    bgzip -c results/${sample}.vcf > "$vcf_gz"
    tabix -p vcf "$vcf_gz"
    rm -f results/${sample}.vcf
  fi
done

# Collapse step
collapsed=results/collapsed.tsv
needs_rebuild=0
if [ ! -f "$collapsed" ]; then needs_rebuild=1; fi
for sample in "${samples[@]}"; do
  vcf_gz=results/${sample}.vcf.gz
  if [ -f "$vcf_gz" ] && ( [ ! -f "$collapsed" ] || [ "$vcf_gz" -nt "$collapsed" ] ); then
    needs_rebuild=1; break
  fi
done

if ((needs_rebuild)); then
  tmp=$(mktemp)
  printf "sample\tchrom\tpos\tref\talt\taf\n" > "$tmp"
  for sample in "${samples[@]}"; do
    bcftools query -f '{sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' results/${sample}.vcf.gz >> "$tmp"
  done
  mv "$tmp" "$collapsed"
fi

exit 0