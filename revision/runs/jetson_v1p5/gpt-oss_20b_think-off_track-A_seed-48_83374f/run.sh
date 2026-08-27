#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

mkdir -p results

# Reference indexing
if [ ! -f data/ref/chrM.fa.bwt ]; then
  bwa index data/ref/chrM.fa
fi
if [ ! -f data/ref/chrM.fa.fai ]; then
  samtools faidx data/ref/chrM.fa
fi

for sample in "${SAMPLES[@]}"; do
  bam=results/${sample}.bam
  bai=results/${sample}.bam.bai
  vcf_gz=results/${sample}.vcf.gz
  tbi=results/${sample}.vcf.gz.tbi

  if [ ! -f "$bai" ]; then
    RG=$(printf "@RG\tID:%s\tSM:%s\tLB:%s\tPL:ILLUMINA" "$sample" "$sample" "$sample")
    bwa mem -t $THREADS -R "$RG" data/ref/chrM.fa data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz | samtools sort -@ $THREADS -o "$bam" -
    samtools index -@ $THREADS "$bam"
  fi

  if [ ! -f "$tbi" ]; then
    lofreq call-parallel --pp-threads $THREADS -f data/ref/chrM.fa -o results/${sample}.vcf "$bam"
    samtools bgzip -f results/${sample}.vcf
    tabix -p vcf "$vcf_gz"
  fi
done

if [ ! -f results/collapsed.tsv ]; then
  printf 'sample\tchrom\tpos\tref\talt\taf\n' > results/collapsed.tsv
fi

for sample in "${SAMPLES[@]}"; do
  vcf_gz=results/${sample}.vcf.gz
  bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "$vcf_gz" | while IFS=$'\t' read -r chrom pos ref alt af; do
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$sample" "$chrom" "$pos" "$ref" "$alt" "$af"
  done >> results/collapsed.tsv
done

exit 0