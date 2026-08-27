#!/usr/bin/env bash
set -euo pipefail

THREADS=4
samples=(M117-bl M117-ch M117C1-bl M117C1-ch)

mkdir -p results

# Reference indexing
if [[ ! -f data/ref/chrM.fa.fai ]]; then
  samtools faidx data/ref/chrM.fa
fi
if [[ ! -f data/ref/chrM.fa.amb || ! -f data/ref/chrM.fa.ann || ! -f data/ref/chrM.fa.bwt || ! -f data/ref/chrM.fa.pac || ! -f data/ref/chrM.fa.sa ]]; then
  bwa index data/ref/chrM.fa
fi

for sample in "${samples[@]}"; do
  bam=results/${sample}.bam
  if [[ ! -f "$bam" ]] || [[ data/raw/${sample}_1.fq.gz -nt "$bam" ]]; then
    bwa mem -t $THREADS -R "@RG\\tID:$sample\\tSM:$sample\\tLB:$sample\\tPL:ILLUMINA" \
      data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz |
      samtools sort -@ $THREADS -o "$bam"
  fi

  bai=results/${sample}.bam.bai
  if [[ ! -f "$bai" ]] || [[ "$bam" -nt "$bai" ]]; then
    samtools index -@ $THREADS "$bam"
  fi

  vcf_gz=results/${sample}.vcf.gz
  tbi=results/${sample}.vcf.gz.tbi
  if [[ ! -f "$tbi" ]] || [[ "$bam" -nt "$tbi" ]]; then
    rm -f results/${sample}.vcf
    lofreq call-parallel --pp-threads $THREADS --verbose \
      --ref data/ref/chrM.fa --out results/${sample}.vcf \
      --sig --bonf "$bam"
    bgzip -c results/${sample}.vcf > "$vcf_gz"
    rm -f results/${sample}.vcf
    tabix -p vcf "$vcf_gz"
  fi
done

collapsed=results/collapsed.tsv
if [[ ! -f "$collapsed" ]] || [[ $(find results/*.vcf.gz -newer "$collapsed" | wc -l) -gt 0 ]]; then
  rm -f "$collapsed"
  printf "sample\tchrom\tpos\tref\talt\taf\n" > "$collapsed"
  for sample in "${samples[@]}"; do
    bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' results/${sample}.vcf.gz |
      awk -v s="$sample" '{print s"\t"$0}' >> "$collapsed"
  done
fi

exit 0