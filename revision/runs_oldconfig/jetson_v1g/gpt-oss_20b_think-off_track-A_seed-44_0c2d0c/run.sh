#!/usr/bin/env bash
set -euo pipefail

THREADS=4
samples=(M117-bl M117-ch M117C1-bl M117C1-ch)

mkdir -p results

ref_fa=data/ref/chrM.fa
if [ ! -f "${ref_fa}.fai" ]; then
  samtools faidx "$ref_fa"
fi
if [ ! -f "${ref_fa}.bwt" ]; then
  bwa index "$ref_fa"
fi

for sample in "${samples[@]}"; do
  bam=results/${sample}.bam
  vcf_gz=results/${sample}.vcf.gz
  if [ -f "$vcf_gz.tbi" ]; then
    continue
  fi

  bwa mem -t $THREADS \
    -R "@RG\\tID:${sample}\\tSM:${sample}\\tLB:${sample}\\tPL:ILLUMINA" \
    data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz | \
    samtools sort -@ $THREADS -o "$bam"

  samtools index -@ $THREADS "$bam"

  vcf_uncompressed=${vcf_gz%.gz}
  lofreq call-parallel --pp-threads $THREADS --verbose \
    --ref "$ref_fa" --out "$vcf_uncompressed" --sig --bonf "$bam"

  bgzip -c "$vcf_uncompressed" > "$vcf_gz"
  tabix -p vcf "$vcf_gz"
  rm "$vcf_uncompressed"
done

collapsed=results/collapsed.tsv
rebuild=false
if [ ! -f "$collapsed" ]; then
  rebuild=true
else
  for sample in "${samples[@]}"; do
    if [ "results/${sample}.vcf.gz" -nt "$collapsed" ]; then
      rebuild=true
      break
    fi
  done
fi

if $rebuild; then
  tmp=$(mktemp)
  for sample in "${samples[@]}"; do
    bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" results/${sample}.vcf.gz >> "$tmp"
  done
  printf "sample\tchrom\tpos\tref\talt\taf\n" > "$collapsed"
  cat "$tmp" >> "$collapsed"
  rm "$tmp"
fi

exit 0