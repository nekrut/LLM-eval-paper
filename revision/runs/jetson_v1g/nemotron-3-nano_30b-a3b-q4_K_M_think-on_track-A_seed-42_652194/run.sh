#!/usr/bin/env bash
set -euo pipefail
THREADS=4
samples=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
mkdir -p results
if [ ! -e data/ref/chrM.fa.bwt ]; then
  samtools faidx data/ref/chrM.fa
  bwa index data/ref/chrM.fa
fi
for sample in "${samples[@]}"; do
  if [ ! -e results/${sample}.bam.bai ]; then
    bwa mem -t 4 -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" data/ref/chrM.fa data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz | samtools sort -@ 4 -o results/${sample}.bam
    samtools index -@ 4 results/${sample}.bam
  fi
  if [ ! -e results/${sample}.vcf.gz.tbi ]; then
    lofreq call-parallel --pp-threads 4 --verbose --ref data/ref/chrM.fa --out results/${sample}.vcf --sig --bonf results/${sample}.bam
    bgzip -c results/${sample}.vcf > results/${sample}.vcf.gz
    tabix -p vcf results/${sample}.vcf.gz
    rm -f results/${sample}.vcf
  fi
done
if [ ! -e results/collapsed.tsv ]; then
  cat <<'EOF' > results/collapsed.tsv
sample	chrom	pos	ref	alt	af
EOF
  for sample in "${samples[@]}"; do
    bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' results/${sample}.vcf.gz |
      while IFS= read -r line; do
        printf '%s\t%s\n' "${sample}" "$line" >> results/collapsed.tsv
      done
  done
fi