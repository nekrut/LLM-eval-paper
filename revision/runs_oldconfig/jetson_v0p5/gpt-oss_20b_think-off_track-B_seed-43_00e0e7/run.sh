#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)

mkdir -p results

all_present=true
for s in "${SAMPLES[@]}"; do
  for f in results/${s}.bam results/${s}.bam.bai results/${s}.vcf.gz results/${s}.vcf.gz.tbi; do
    if [[ ! -f $f ]]; then all_present=false; break 2; fi
  done
done

if [[ "$all_present" == true && -f results/collapsed.tsv ]]; then
  exit 0
fi

map_sample() {
  local sample=$1
  local bam=results/${sample}.bam
  local bai=${bam}.bai
  if [[ -f $bam && -f $bai ]]; then return; fi
  bwa mem -t "$THREADS" data/ref/chrM.fa data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz | \
    samtools view -@ "$THREADS" -Sb - | \
    samtools sort -@ "$THREADS" -o "$bam"
  samtools index "$bam"
}

call_variants() {
  local sample=$1
  local vcf=results/${sample}.vcf.gz
  local tbi=${vcf}.tbi
  if [[ -f $vcf && -f $tbi ]]; then return; fi
  local tmp_vcf=results/${sample}.vcf
  lofreq call --threads "$THREADS" -f data/ref/chrM.fa -i results/${sample}.bam -o "$tmp_vcf"
  bcftools view -O z -o "$vcf" "$tmp_vcf"
  tabix -p vcf "$vcf"
  rm -f "$tmp_vcf"
}

for s in "${SAMPLES[@]}"; do
  map_sample "$s"
  call_variants "$s"
done

collapsed=results/collapsed.tsv
tmp_collapsed=$(mktemp)

printf "sample\tchrom\tpos\tref\talt\taf\n" > "$tmp_collapsed"

for s in "${SAMPLES[@]}"; do
  vcf=results/${s}.vcf.gz
  bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "$vcf" | awk -v sample="$s" '{print sample"\t"$0}' >> "$tmp_collapsed"
done

mv "$tmp_collapsed" "$collapsed"

exit 0