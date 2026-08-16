#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES="M117-bl M117-ch M117C1-bl M117C1-ch"

mkdir -p results

# Reference indexing
if [[ ! -s data/ref/chrM.fa.fai ]]; then
  samtools faidx data/ref/chrM.fa
fi
if [[ ! -s data/ref/chrM.fa.amb ]]; then
  bwa index data/ref/chrM.fa
fi

for s in $SAMPLES; do
  bam=results/${s}.bam
  bai=${bam}.bai
  vcfz=results/${s}.vcf.gz
  tbi=${vcfz}.tbi

  # Alignment
  if [[ ! -s $bam ]]; then
    bwa mem -t $THREADS -R "@RG\\tID:${s}\\tSM:${s}\\tLB:${s}\\tPL:ILLUMINA" \
      data/raw/${s}_1.fq.gz data/raw/${s}_2.fq.gz | \
      samtools sort -@ $THREADS -o $bam
  fi

  # BAM index
  if [[ ! -s $bai ]]; then
    samtools index -@ $THREADS $bam
  fi

  # Variant calling
  if [[ ! -s $tbi ]]; then
    vcf=results/${s}.vcf
    lofreq call-parallel --pp-threads $THREADS -f data/ref/chrM.fa -b $bam > $vcf
    bgzip -c $vcf > $vcfz
    tabix -p vcf $vcfz
    rm $vcf
  fi
done

# Collapse VCFs into TSV
collapsed=results/collapsed.tsv
needs_rebuild=0
if [[ ! -s $collapsed ]]; then
  needs_rebuild=1
else
  for s in $SAMPLES; do
    vcfz=results/${s}.vcf.gz
    if [[ -s $vcfz && $vcfz -nt $collapsed ]]; then
      needs_rebuild=1
      break
    fi
  done
fi

if ((needs_rebuild)); then
  tmpfile=$(mktemp)
  for s in $SAMPLES; do
    bcftools query -f "${s}\\t%CHROM\\t%POS\\t%REF\\t%ALT\\t%INFO/AF\\n" results/${s}.vcf.gz >> "$tmpfile"
  done
  printf 'sample\tchrom\tpos\tref\talt\taf\n' > $collapsed
  cat "$tmpfile" >> $collapsed
  rm "$tmpfile"
fi

exit 0