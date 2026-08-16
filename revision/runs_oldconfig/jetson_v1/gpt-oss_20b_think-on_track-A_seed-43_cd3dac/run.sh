#!/usr/bin/env bash
set -euo pipefail

THREADS=4
samples=(M117-bl M117-ch M117C1-bl M117C1-ch)

mkdir -p results

# Reference indexing
if [ ! -f data/ref/chrM.fa.fai ]; then
  samtools faidx data/ref/chrM.fa
fi
if [ ! -f data/ref/chrM.fa.bwt ]; then
  bwa index data/ref/chrM.fa
fi

for sample in "${samples[@]}"; do
  bam=results/${sample}.bam
  bai=${bam}.bai
  vcf_gz=results/${sample}.vcf.gz
  fq1=data/raw/${sample}_1.fq.gz
  fq2=data/raw/${sample}_2.fq.gz

  # Alignment
  if [ ! -s "$bam" ] || [ "$bam" -ot "$fq1" ] || [ "$bam" -ot "$fq2" ]; then
    bwa mem -t $THREADS -R "@RG\\tID:${sample}\\tSM:${sample}\\tLB:${sample}\\tPL:ILLUMINA" \
      data/ref/chrM.fa "$fq1" "$fq2" | samtools sort -@ $THREADS -o "$bam"
  fi

  # BAM indexing
  if [ ! -s "$bai" ] || [ "$bai" -ot "$bam" ]; then
    samtools index -@ $THREADS "$bam"
  fi

  # Variant calling
  if [ ! -s "$vcf_gz" ] || [ "$vcf_gz" -ot "$bam" ]; then
    tmp_vcf=results/${sample}.vcf
    lofreq call-parallel --pp-threads $THREADS -f data/ref/chrM.fa -o "$tmp_vcf" "$bam"
    bgzip -c "$tmp_vcf" > "$vcf_gz"
    tabix -p vcf "$vcf_gz"
    rm "$tmp_vcf"
  fi
done

# Collapse step
collapsed=results/collapsed.tsv
need_rebuild=false
if [ ! -s "$collapsed" ]; then
  need_rebuild=true
else
  for sample in "${samples[@]}"; do
    vcf_gz=results/${sample}.vcf.gz
    if [ "$vcf_gz" -ot "$collapsed" ]; then
      need_rebuild=true
      break
    fi
  done
fi

if $need_rebuild; then
  tmpfile=$(mktemp)
  echo -e "sample\tchrom\tpos\tref\talt\taf" > "$tmpfile"
  for sample in "${samples[@]}"; do
    vcf_gz=results/${sample}.vcf.gz
    bcftools query -f '{sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "$vcf_gz" >> "$tmpfile"
  done
  mv "$tmpfile" "$collapsed"
fi

exit 0