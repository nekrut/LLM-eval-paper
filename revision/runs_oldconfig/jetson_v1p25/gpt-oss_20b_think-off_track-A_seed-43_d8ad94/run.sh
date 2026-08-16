#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES="M117-bl M117-ch M117C1-bl M117C1-ch"

# Create results directory if needed
mkdir -p results

# Reference indexing
REF=data/ref/chrM.fa
if [[ ! -f ${REF}.fai ]]; then
  samtools faidx "$REF"
fi
if [[ ! -f ${REF}.bwt ]]; then
  bwa index "$REF"
fi

for sample in $SAMPLES; do
  fq1=data/raw/${sample}_1.fq.gz
  fq2=data/raw/${sample}_2.fq.gz
  bam=results/${sample}.bam
  bai=results/${sample}.bam.bai
  vcf=results/${sample}.vcf
  vcfz=results/${sample}.vcf.gz
  tbiz=results/${sample}.vcf.gz.tbi

  # Alignment and sorting
  needs_align=false
  if [[ ! -f "$bam" ]]; then needs_align=true; fi
  if [[ -f "$bam" ]]; then
    if [[ $(stat -c %Y "$fq1") -gt $(stat -c %Y "$bam") || $(stat -c %Y "$fq2") -gt $(stat -c %Y "$bam") ]]; then
      needs_align=true
    fi
  fi
  if $needs_align; then
    RG='@RG\tID:'$sample'\tSM:'$sample'\tLB:'$sample'\tPL:ILLUMINA'
    bwa mem -t $THREADS -R "$RG" "$REF" "$fq1" "$fq2" | samtools sort -@ $THREADS -o "$bam"
  fi

  # BAM indexing
  needs_index=false
  if [[ ! -f "$bai" ]]; then needs_index=true; fi
  if [[ -f "$bam" && $(stat -c %Y "$bam") -gt $(stat -c %Y "$bai") ]]; then
    needs_index=true
  fi
  if $needs_index; then
    samtools index -@ $THREADS "$bam"
  fi

  # Variant calling
  needs_call=false
  if [[ ! -f "$tbiz" ]]; then needs_call=true; fi
  if [[ -f "$bam" && $(stat -c %Y "$bam") -gt $(stat -c %Y "$tbiz") ]]; then
    needs_call=true
  fi
  if $needs_call; then
    lofreq call-parallel --pp-threads $THREADS -f "$REF" -o "$vcf" "$bam"
    bcftools view -Oz -o "$vcfz" "$vcf"
    tabix -p vcf "$vcfz"
    rm -f "$vcf"
  fi
done

# Collapse VCFs into TSV
collapsed=results/collapsed.tsv
rebuild=false
if [[ ! -f "$collapsed" ]]; then
  rebuild=true
else
  for sample in $SAMPLES; do
    vcfz=results/${sample}.vcf.gz
    if [[ $(stat -c %Y "$vcfz") -gt $(stat -c %Y "$collapsed") ]]; then
      rebuild=true
      break
    fi
  done
fi

if $rebuild; then
  {
    printf "sample\tchrom\tpos\tref\talt\taf\n"
    for sample in $SAMPLES; do
      vcfz=results/${sample}.vcf.gz
      bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "$vcfz"
    done
  } > "$collapsed"
fi

exit 0