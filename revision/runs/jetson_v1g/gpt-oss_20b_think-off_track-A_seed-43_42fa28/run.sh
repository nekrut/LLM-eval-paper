#!/usr/bin/env bash
set -euo pipefail

THREADS=4
samples=(M117-bl M117-ch M117C1-bl M117C1-ch)

mkdir -p results

# Reference indexing
if [ ! -f data/ref/chrM.fa.fai ]; then
  samtools faidx data/ref/chrM.fa
fi
if [ ! -f data/ref/chrM.fa.bwt ]; then
  bwa index data/ref/chrM.fa
fi

for sample in "${samples[@]}"; do
  bam=results/${sample}.bam
  bai=results/${sample}.bam.bai
  vcf_gz=results/${sample}.vcf.gz
  vcf_tbi=results/${sample}.vcf.gz.tbi

  if [ ! -f "$bam" ]; then
    bwa mem -t $THREADS -R "@RG\\tID:${sample}\\tSM:${sample}\\tLB:${sample}\\tPL:ILLUMINA" \
      data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz | \
      samtools sort -@ $THREADS -o "$bam"
  fi

  if [ ! -f "$bai" ]; then
    samtools index -@ $THREADS "$bam"
  fi

  if [ ! -f "$vcf_tbi" ]; then
    lofreq call-parallel --pp-threads $THREADS --verbose \
      --ref data/ref/chrM.fa --out results/${sample}.vcf \
      --sig --bonf "$bam"
    bgzip -c results/${sample}.vcf > "$vcf_gz"
    tabix -p vcf "$vcf_gz"
    rm results/${sample}.vcf
  fi
done

collapsed=results/collapsed.tsv
latest_vcf_mtime=0
for sample in "${samples[@]}"; do
  mtime=$(stat -c %Y results/${sample}.vcf.gz)
  if (( mtime > latest_vcf_mtime )); then
    latest_vcf_mtime=$mtime
  fi
done

if [ -f "$collapsed" ]; then
  collapsed_mtime=$(stat -c %Y "$collapsed")
  if (( collapsed_mtime >= latest_vcf_mtime )); then
    exit 0
  fi
fi

tmpfile=$(mktemp)
for sample in "${samples[@]}"; do
  bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" results/${sample}.vcf.gz >> "$tmpfile"
done

cat <<'EOF' > "$collapsed"
sample	chrom	pos	ref	alt	af
EOF
cat "$tmpfile" >> "$collapsed"
rm "$tmpfile"

exit 0