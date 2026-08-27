#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)

mkdir -p results

# Reference indexing
if [[ ! -s data/ref/chrM.fa.fai ]]; then
  samtools faidx data/ref/chrM.fa
fi
if [[ ! -s data/ref/chrM.fa.bwt ]]; then
  bwa index data/ref/chrM.fa
fi

for sample in "${SAMPLES[@]}"; do
  bam=results/${sample}.bam
  if [[ ! -s "$bam" ]] || \
     [[ data/raw/${sample}_1.fq.gz -nt "$bam" ]] || \
     [[ data/raw/${sample}_2.fq.gz -nt "$bam" ]]; then
    bwa mem -t $THREADS -R "@RG\\tID:${sample}\\tSM:${sample}\\tLB:${sample}\\tPL:ILLUMINA" \
      data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz |
      samtools sort -@ $THREADS -o "$bam"
  fi

  bai=results/${sample}.bam.bai
  if [[ ! -s "$bai" ]] || [[ "$bam" -nt "$bai" ]]; then
    samtools index -@ $THREADS "$bam"
  fi

  vcf_tbi=results/${sample}.vcf.gz.tbi
  if [[ ! -s "$vcf_tbi" ]] || [[ "$bam" -nt "$vcf_tbi" ]]; then
    vcf_uncompressed=results/${sample}.vcf
    lofreq call-parallel --pp-threads $THREADS --verbose \
      --ref data/ref/chrM.fa --out "$vcf_uncompressed" \
      --sig --bonf "$bam"
    bgzip -c "$vcf_uncompressed" > "${vcf_uncompressed}.gz"
    tabix -p vcf "${vcf_uncompressed}.gz"
    rm "$vcf_uncompressed"
  fi
done

collapsed=results/collapsed.tsv
need_collapse=false
if [[ ! -s "$collapsed" ]]; then need_collapse=true; fi
for sample in "${SAMPLES[@]}"; do
  if [[ results/${sample}.vcf.gz -nt "$collapsed" ]]; then need_collapse=true; break; fi
done

if $need_collapse; then
  tmp=$(mktemp)
  for sample in "${SAMPLES[@]}"; do
    while IFS= read -r line; do
      printf "%s\t%s\n" "$sample" "$line"
    done < <(bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' results/${sample}.vcf.gz) >> "$tmp"
  done
  printf "sample\tchrom\tpos\tref\talt\taf\n" > "$collapsed"
  cat "$tmp" >> "$collapsed"
  rm "$tmp"
fi