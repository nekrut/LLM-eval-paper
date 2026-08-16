#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)

mkdir -p results

needs_run() {
  local out=$1; shift
  local inputs=("$@")
  if [[ ! -e $out ]]; then return 0; fi
  for inp in "${inputs[@]}"; do
    [[ -e $inp ]] || continue
    if [[ $(stat -c %Y "$inp") -gt $(stat -c %Y "$out") ]]; then return 0; fi
  done
  return 1
}

REF=data/ref/chrM.fa

if needs_run "${REF}.fai" "$REF"; then
  samtools faidx "$REF"
fi

if needs_run "${REF}.bwt" "$REF"; then
  bwa index "$REF"
fi

for sample in "${SAMPLES[@]}"; do
  bam=results/${sample}.bam
  bai=results/${sample}.bam.bai
  vcf_uncompressed=results/${sample}.vcf
  vcf_gz=results/${sample}.vcf.gz
  vcf_tbi=results/${sample}.vcf.gz.tbi

  fq1=data/raw/${sample}_1.fq.gz
  fq2=data/raw/${sample}_2.fq.gz

  if needs_run "$bam" "$fq1" "$fq2"; then
    bwa mem -t $THREADS -R "@RG\\tID:${sample}\\tSM:${sample}\\tLB:${sample}\\tPL:ILLUMINA" \
      "$REF" "$fq1" "$fq2" | samtools sort -@ $THREADS -o "$bam"
  fi

  if needs_run "$bai" "$bam"; then
    samtools index -@ $THREADS "$bam"
  fi

  if needs_run "$vcf_gz" "$bam" || [[ ! -e $vcf_tbi ]]; then
    lofreq call-parallel --pp-threads $THREADS -f "$REF" -o "$vcf_uncompressed" "$bam"
    bgzip -c "$vcf_uncompressed" > "$vcf_gz"
    tabix -p vcf "$vcf_gz"
    rm -f "$vcf_uncompressed"
  fi
done

collapsed=results/collapsed.tsv
vcf_files=()
for sample in "${SAMPLES[@]}"; do
  vcf_files+=("results/${sample}.vcf.gz")
done

all_exist=true
for f in "${vcf_files[@]}"; do
  [[ -e $f ]] || { all_exist=false; break; }
done

if $all_exist && needs_run "$collapsed" "${vcf_files[@]}"; then
  printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed"
  for sample in "${SAMPLES[@]}"; do
    bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" \
      results/${sample}.vcf.gz >> "$collapsed"
  done
fi

exit 0