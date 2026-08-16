#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)

mkdir -p results

# Reference indexing
if [ ! -s data/ref/chrM.fa.fai ]; then
  samtools faidx data/ref/chrM.fa
fi
if [ ! -s data/ref/chrM.fa.bwt ]; then
  bwa index data/ref/chrM.fa
fi

for sample in "${SAMPLES[@]}"; do
  bam=results/${sample}.bam
  bai=results/${sample}.bam.bai
  vcf_gz=results/${sample}.vcf.gz
  vcf=results/${sample}.vcf

  # Alignment
  if [[ ! -s "$bam" ]] || \
     [[ data/raw/${sample}_1.fq.gz -nt "$bam" ]] || \
     [[ data/raw/${sample}_2.fq.gz -nt "$bam" ]]; then
    bwa mem -t $THREADS -R "@RG\\tID:${sample}\\tSM:${sample}\\tLB:${sample}\\tPL:ILLUMINA" \
      data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz | \
      samtools sort -@ $THREADS -o "$bam"
  fi

  # BAM index
  if [[ ! -s "$bai" ]] || [[ "$bam" -nt "$bai" ]]; then
    samtools index -@ $THREADS "$bam"
  fi

  # Variant calling
  if [[ ! -s "$vcf_gz" ]] || [[ "$bam" -nt "$vcf_gz" ]]; then
    lofreq call-parallel --pp-threads $THREADS \
      -f data/ref/chrM.fa -b "$bam" -o "$vcf"
    bcftools view -O z -o "${vcf}.gz" "$vcf"
    tabix -p vcf "${vcf}.gz"
    rm -f "$vcf"
  fi
done

# Collapse VCFs into TSV
collapsed=results/collapsed.tsv
if [[ ! -s "$collapsed" ]] || \
   [[ results/M117-bl.vcf.gz -nt "$collapsed" ]] || \
   [[ results/M117-ch.vcf.gz -nt "$collapsed" ]] || \
   [[ results/M117C1-bl.vcf.gz -nt "$collapsed" ]] || \
   [[ results/M117C1-ch.vcf.gz -nt "$collapsed" ]]; then
  printf 'sample\tchrom\tpos\tref\talt\taf\n' >"$collapsed"
  for sample in "${SAMPLES[@]}"; do
    bcftools query -f "${sample}\\t%CHROM\\t%POS\\t%REF\\t%ALT\\t%INFO/AF\\n" results/${sample}.vcf.gz >> "$collapsed"
  done
fi

exit 0