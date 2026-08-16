#!/usr/bin/env bash
set -euo pipefail

THREADS=4

mkdir -p results

# Index reference if needed
if [ ! -f data/ref/chrM.fa.fai ]; then
  samtools faidx data/ref/chrM.fa
fi

# BWA index if missing
for idx in data/ref/chrM.fa.bwt data/ref/chrM.fa.amb data/ref/chrM.fa.pac data/ref/chrM.fa.sa; do
  if [ ! -f "$idx" ]; then
    bwa index data/ref/chrM.fa
    break
  fi
done

samples=(M117-bl M117-ch M117C1-bl M117C1-ch)

for sample in "${samples[@]}"; do
  bam=results/${sample}.bam
  vcf=results/${sample}.vcf.gz

  if [ ! -f "$bam" ]; then
    bwa mem -t $THREADS data/ref/chrM.fa \
      data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz | \
      samtools view -bS - | \
      samtools sort -@ $THREADS -o "$bam"
    samtools index "$bam"
  fi

  if [ ! -f "$vcf" ]; then
    lofreq call --call-indels -f data/ref/chrM.fa "$bam" | \
      bcftools sort -O z -o "$vcf"
    tabix -p vcf "$vcf"
  fi
done

collapsed=results/collapsed.tsv
regen=false
if [ ! -f "$collapsed" ]; then
  regen=true
else
  for sample in "${samples[@]}"; do
    if [ "results/${sample}.vcf.gz" -nt "$collapsed" ]; then
      regen=true
      break
    fi
  done
fi

if $regen; then
  tmp=$(mktemp)
  for sample in "${samples[@]}"; do
    vcf=results/${sample}.vcf.gz
    bcftools query -f '%CHROM\t%POS\t%REF\t[%ALT]\t[%AF]\n' "$vcf" | \
      awk -v s="$sample" '{print s"\t"$0}' >> "$tmp"
  done
  printf "sample\tchrom\tpos\tref\talt\taf\n" > "$collapsed"
  cat "$tmp" >> "$collapsed"
  rm "$tmp"
fi

exit 0