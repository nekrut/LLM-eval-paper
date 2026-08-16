#!/usr/bin/env bash
set -euo pipefail

THREADS=4
RAWDIR="data/raw"
OUTDIR="results"
REFDIR="${OUTDIR}/ref"
REF="${REFDIR}/chrM.fa"

SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)

mkdir -p "$OUTDIR" "$REFDIR"

# Stage reference under results/ and build indices there (idempotent).
if [[ ! -s "$REF" ]]; then
  cp "data/ref/chrM.fa" "${REF}.tmp"
  mv "${REF}.tmp" "$REF"
fi
if [[ ! -s "${REF}.bwt" ]]; then
  bwa index "$REF"
fi
if [[ ! -s "${REF}.fai" ]]; then
  samtools faidx "$REF"
fi

for sample in "${SAMPLES[@]}"; do
  fq1="${RAWDIR}/${sample}_1.fq.gz"
  fq2="${RAWDIR}/${sample}_2.fq.gz"

  bam="${OUTDIR}/${sample}.bam"
  bai="${OUTDIR}/${sample}.bam.bai"
  vcf="${OUTDIR}/${sample}.vcf.gz"
  tbi="${OUTDIR}/${sample}.vcf.gz.tbi"

  if [[ ! -s "$bam" || ! -s "$bai" ]]; then
    bwa mem -t "$THREADS" \
      -R "@RG\tID:${sample}\tSM:${sample}\tPL:ILLUMINA" \
      "$REF" "$fq1" "$fq2" \
      | samtools sort -@ "$THREADS" -o "${bam}.tmp" -
    mv "${bam}.tmp" "$bam"
    samtools index "$bam"
  fi
  if [[ ! -s "$bai" ]]; then
    samtools index "$bam"
  fi

  if [[ ! -s "$vcf" || ! -s "$tbi" ]]; then
    indel_bam="${OUTDIR}/${sample}.indelqual.bam"
    indel_bai="${indel_bam}.bai"

    if [[ ! -s "$indel_bam" ]]; then
      lofreq indelqual --dindel -f "$REF" -o "${indel_bam}.tmp" "$bam"
      mv "${indel_bam}.tmp" "$indel_bam"
    fi
    if [[ ! -s "$indel_bai" ]]; then
      samtools index "$indel_bam"
    fi

    tmp_vcf="${OUTDIR}/.${sample}.vcf"
    rm -f "$tmp_vcf" "${tmp_vcf}.gz"
    lofreq call --call-indels -f "$REF" -o "$tmp_vcf" "$indel_bam"
    bgzip -f "$tmp_vcf"
    mv "${tmp_vcf}.gz" "$vcf"
    tabix -f -p vcf "$vcf"
  fi
done

collapsed="${OUTDIR}/collapsed.tsv"
collapsed_tmp="${OUTDIR}/.collapsed.tsv.tmp"

{
  printf "sample\tchrom\tpos\tref\talt\taf\n"
  for sample in "${SAMPLES[@]}"; do
    vcf="${OUTDIR}/${sample}.vcf.gz"
    bcftools query -f "%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "$vcf" \
      | awk -v s="$sample" 'BEGIN{OFS="\t"}{print s,$1,$2,$3,$4,$5}'
  done
} > "$collapsed_tmp"

mv "$collapsed_tmp" "$collapsed"