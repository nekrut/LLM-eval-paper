#!/usr/bin/env bash
set -euo pipefail

THREADS=4
RAW="data/raw"
REF="data/ref/chrM.fa"
OUT="results"
LOG="${OUT}/logs"

mkdir -p "${OUT}" "${LOG}"

if [[ ! -f "${REF}.bwt" ]]; then
  bwa index "${REF}" &> "${LOG}/bwa_index.log"
fi

if [[ ! -f "${REF}.fai" ]]; then
  samtools faidx "${REF}" &> "${LOG}/faidx.log"
fi

SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)

for sample in "${SAMPLES[@]}"; do
  bam="${OUT}/${sample}.bam"
  bai="${OUT}/${sample}.bam.bai"
  vcf="${OUT}/${sample}.vcf.gz"
  tbi="${OUT}/${sample}.vcf.gz.tbi"

  fq1="${RAW}/${sample}_1.fq.gz"
  fq2="${RAW}/${sample}_2.fq.gz"

  if [[ ! -s "${bam}" || ! -s "${bai}" ]]; then
    rg=$(printf '@RG\tID:%s\tSM:%s\tPL:ILLUMINA' "${sample}" "${sample}")
    bwa mem -t "${THREADS}" -R "${rg}" "${REF}" "${fq1}" "${fq2}" \
      2> "${LOG}/${sample}.bwa.log" \
      | samtools sort -@ "${THREADS}" -o "${bam}" - \
      2> "${LOG}/${sample}.sort.log"
    samtools index -@ "${THREADS}" "${bam}"
  fi

  if [[ ! -s "${vcf}" || ! -s "${tbi}" ]]; then
    raw_vcf="${OUT}/${sample}.raw.vcf"
    lofreq call -f "${REF}" -o "${raw_vcf}" "${bam}" \
      &> "${LOG}/${sample}.lofreq.log"
    bcftools view -Oz -o "${vcf}" "${raw_vcf}" &>> "${LOG}/${sample}.lofreq.log"
    tabix -f -p vcf "${vcf}"
    rm -f "${raw_vcf}"
  fi
done

collapsed="${OUT}/collapsed.tsv"
if [[ ! -s "${collapsed}" ]]; then
  tmp_collapsed="${collapsed}.tmp"
  printf 'sample\tchrom\tpos\tref\talt\taf\n' > "${tmp_collapsed}"
  for sample in "${SAMPLES[@]}"; do
    vcf="${OUT}/${sample}.vcf.gz"
    bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "${vcf}" \
      >> "${tmp_collapsed}"
  done
  mv "${tmp_collapsed}" "${collapsed}"
fi