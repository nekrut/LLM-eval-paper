#!/usr/bin/env bash
set -euo pipefail

THREADS=4
REF="data/ref/chrM.fa"
RAW_DIR="data/raw"
OUT_DIR="results"
TMP_DIR="${OUT_DIR}/tmp"

mkdir -p "${OUT_DIR}" "${TMP_DIR}"

SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)

# Index the reference once (idempotent: skip if index files already exist)
if [[ ! -s "${REF}.bwt" ]]; then
    bwa index "${REF}"
fi
if [[ ! -s "${REF}.fai" ]]; then
    samtools faidx "${REF}"
fi

for s in "${SAMPLES[@]}"; do
    R1="${RAW_DIR}/${s}_1.fq.gz"
    R2="${RAW_DIR}/${s}_2.fq.gz"
    BAM="${OUT_DIR}/${s}.bam"
    BAI="${BAM}.bai"
    VCF="${OUT_DIR}/${s}.vcf.gz"
    TBI="${VCF}.tbi"

    if [[ ! -s "${BAI}" ]]; then
        bwa mem -t "${THREADS}" \
            -R "@RG\tID:${s}\tSM:${s}\tPL:ILLUMINA\tLB:${s}" \
            "${REF}" "${R1}" "${R2}" \
        | samtools sort -@ "${THREADS}" -o "${BAM}" -
        samtools index "${BAM}"
    fi

    if [[ ! -s "${TBI}" ]]; then
        IQBAM="${TMP_DIR}/${s}.iq.bam"
        lofreq indelqual --dindel -f "${REF}" -o "${IQBAM}" "${BAM}"
        samtools index "${IQBAM}"

        RAWVCF="${TMP_DIR}/${s}.vcf"
        lofreq call-parallel --pp-threads "${THREADS}" -f "${REF}" \
            --call-indels -o "${RAWVCF}" "${IQBAM}"

        bcftools view -Oz -o "${VCF}" "${RAWVCF}"
        tabix -f -p vcf "${VCF}"
    fi
done

COLLAPSED="${OUT_DIR}/collapsed.tsv"
{
    printf 'sample\tchrom\tpos\tref\talt\taf\n'
    for s in "${SAMPLES[@]}"; do
        bcftools query -f "${s}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "${OUT_DIR}/${s}.vcf.gz"
    done
} > "${COLLAPSED}"

rm -rf "${TMP_DIR}"