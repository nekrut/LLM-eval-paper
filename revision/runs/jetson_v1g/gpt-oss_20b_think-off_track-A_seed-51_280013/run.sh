#!/usr/bin/env bash
set -euo pipefail

THREADS=4
samples=(M117-bl M117-ch M117C1-bl M117C1-ch)

mkdir -p results

# Reference indexing
if [[ ! -s data/ref/chrM.fa.fai ]]; then
  samtools faidx data/ref/chrM.fa
fi
if [[ ! -s data/ref/chrM.fa.bwt ]]; then
  bwa index data/ref/chrM.fa
fi

for sample in "${samples[@]}"; do
  fq1=data/raw/${sample}_1.fq.gz
  fq2=data/raw/${sample}_2.fq.gz
  bam=results/${sample}.bam
  bai=${bam}.bai
  vcf=results/${sample}.vcf
  vcf_gz=${vcf}.gz
  vcf_tbi=${vcf_gz}.tbi

  # Alignment
  if [[ ! -s "$bam" || "$fq1" -nt "$bam" || "$fq2" -nt "$bam" ]]; then
    bwa mem -t $THREADS -R "@RG\\tID:${sample}\\tSM:${sample}\\tLB:${sample}\\tPL:ILLUMINA" \
      "$fq1" "$fq2" | samtools sort -@ $THREADS -o "$bam"
  fi

  # BAM index
  if [[ ! -s "$bai" || "$bam" -nt "$bai" ]]; then
    samtools index -@ $THREADS "$bam"
  fi

  # Variant calling
  if [[ ! -s "$vcf_tbi" || "$bam" -nt "$vcf_tbi" ]]; then
    lofreq call-parallel --pp-threads $THREADS --verbose \
      --ref data/ref/chrM.fa --out "$vcf" \
      --sig --bonf \
      "$bam"
    bgzip -c "$vcf" > "$vcf_gz"
    tabix -p vcf "$vcf_gz"
    rm "$vcf"
  fi
done

# Collapsed table
collapsed=results/collapsed.tsv
needs_collapsed=0
for sample in "${samples[@]}"; do
  vcf_tbi=results/${sample}.vcf.gz.tbi
  if [[ -e $vcf_tbi && $vcf_tbi -nt "$collapsed" ]]; then
    needs_collapsed=1
    break
  fi
done

if [[ ! -s "$collapsed" || $needs_collapsed -eq 1 ]]; then
  > "$collapsed"
  printf "sample\tchrom\tpos\tref\talt\taf\n" >> "$collapsed"
  for sample in "${samples[@]}"; do
    bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' results/${sample}.vcf.gz | \
      awk -v s="$sample" '{print s"\t"$0}' >> "$collapsed"
  done
fi