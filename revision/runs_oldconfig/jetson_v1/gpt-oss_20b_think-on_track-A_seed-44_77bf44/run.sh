#!/usr/bin/env bash
set -euo pipefail

THREADS=4
samples=(M117-bl M117-ch M117C1-bl M117C1-ch)

mkdir -p results

# Reference indexing
ref=data/ref/chrM.fa
if [[ ! -f ${ref}.fai || ! -f ${ref}.amb ]]; then
  samtools faidx "$ref"
  bwa index "$ref"
fi

# Per-sample processing
for sample in "${samples[@]}"; do
  bam=results/${sample}.bam
  bai=results/${sample}.bam.bai
  vcf_gz=results/${sample}.vcf.gz
  tbi=results/${sample}.vcf.gz.tbi

  if [[ -f "$tbi" ]]; then
    continue
  fi

  bwa mem -t "$THREADS" \
    -R "@RG\\tID:${sample}\\tSM:${sample}\\tLB:${sample}\\tPL:ILLUMINA" \
    data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz | \
    samtools sort -@ "$THREADS" -o "$bam"

  samtools index -@ "$THREADS" "$bam"

  lofreq call-parallel --pp-threads "$THREADS" -f "$ref" "$bam" > results/${sample}.vcf

  bcftools view -O z -o "$vcf_gz" results/${sample}.vcf
  tabix -p vcf "$vcf_gz"
  rm results/${sample}.vcf
done

# Collapse step
collapsed=results/collapsed.tsv
rebuild=false
if [[ ! -f "$collapsed" ]]; then
  rebuild=true
else
  for sample in "${samples[@]}"; do
    if [[ $(stat -c %Y results/${sample}.vcf.gz) -gt $(stat -c %Y "$collapsed") ]]; then
      rebuild=true; break
    fi
  done
fi

if $rebuild; then
  tmp=$(mktemp)
  printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$tmp"
  for sample in "${samples[@]}"; do
    bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' results/${sample}.vcf.gz | \
      awk -v s="$sample" '{print s"\t"$0}' >> "$tmp"
  done
  mv "$tmp" "$collapsed"
fi

exit 0