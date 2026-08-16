#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
REF="data/ref/chrM.fa"

mkdir -p results

if [[ ! -f "${REF}.bwt" || ! -f "${REF}.amb" || ! -f "${REF}.ann" || ! -f "${REF}.pac" || ! -f "${REF}.sa" ]]; then
    bwa index "${REF}"
fi

if [[ ! -f "${REF}.fai" ]]; then
    samtools faidx "${REF}"
fi

for sample in "${SAMPLES[@]}"; do
    bam="results/${sample}.bam"
    bai="results/${sample}.bam.bai"
    vcf="results/${sample}.vcf"
    vcf_gz="results/${sample}.vcf.gz"
    tbi="results/${sample}.vcf.gz.tbi"

    if [[ ! -s "${bam}" || ! -s "${bai}" ]]; then
        bwa mem -t "${THREADS}" \
            -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
            "${REF}" \
            "data/raw/${sample}_1.fq.gz" "data/raw/${sample}_2.fq.gz" \
            | samtools sort -@ "${THREADS}" -o "${bam}" -
        samtools index -@ "${THREADS}" "${bam}"
    fi

    if [[ ! -s "${vcf_gz}" || ! -s "${tbi}" ]]; then
        if [[ ! -s "${vcf_gz}" ]]; then
            lofreq call-parallel --pp-threads "${THREADS}" -f "${REF}" -o "${vcf}" "${bam}"
            bgzip -f "${vcf}"
        fi
        tabix -f -p vcf "${vcf_gz}"
    fi
done

collapsed="results/collapsed.tsv"
tmp="${collapsed}.tmp"

printf 'sample\tchrom\tpos\tref\talt\taf\n' > "${tmp}"

for sample in "${SAMPLES[@]}"; do
    vcf_gz="results/${sample}.vcf.gz"
    bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "${vcf_gz}" \
        | awk -v s="${sample}" 'BEGIN{OFS="\t"}{print s,$0}' >> "${tmp}"
done

mv "${tmp}" "${collapsed}"