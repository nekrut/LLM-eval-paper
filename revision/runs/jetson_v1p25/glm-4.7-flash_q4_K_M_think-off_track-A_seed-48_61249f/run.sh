#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
REF="data/ref/chrM.fa"
RAW="data/raw"

mkdir -p results

# 2. Reference indexing (once)
if [[ ! -f "${REF}.fai" ]]; then
    samtools faidx "${REF}"
fi
if [[ ! -f "${REF}.bwt" ]]; then
    bwa index "${REF}"
fi

# 3. Per-sample alignment with bwa mem
for sample in "${SAMPLES[@]}"; do
    fq1="${RAW}/${sample}_1.fq.gz"
    fq2="${RAW}/${sample}_2.fq.gz"
    bam="results/${sample}.bam"
    bai="results/${sample}.bam.bai"
    vcf="results/${sample}.vcf"
    vcf_gz="results/${sample}.vcf.gz"
    vcf_gz_tbi="results/${sample}.vcf.gz.tbi"

    if [[ -f "${vcf_gz_tbi}" ]]; then
        continue
    fi

    bwa mem -t "${THREADS}" -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" "${fq1}" "${fq2}" \
        | samtools sort -@ "${THREADS}" -o "${bam}"

    samtools index -@ "${THREADS}" "${bam}"

    lofreq call-parallel --pp-threads "${THREADS}" -f "${REF}" -o "${vcf}" "${bam}"

    bgzip -c "${vcf}" > "${vcf_gz}"
    tabix -p vcf "${vcf_gz}"
    rm "${vcf}"
done

# 8. Collapse step
TSV="results/collapsed.tsv"
HEADER="sample\tchrom\tpos\tref\talt\taf"

if [[ -f "${TSV}" ]]; then
    # Check if any input VCF is newer than the TSV
    latest_vcf=0
    for sample in "${SAMPLES[@]}"; do
        vcf_gz="results/${sample}.vcf.gz"
        if [[ -f "${vcf_gz}" ]]; then
            if [[ "${vcf_gz}" -nt "${TSV}" ]]; then
                latest_vcf=1
                break
            fi
        fi
    done
    if [[ "${latest_vcf}" -eq 0 ]]; then
        exit 0
    fi
fi

{
    echo -e "${HEADER}"
    for sample in "${SAMPLES[@]}"; do
        bcftools query -f '{sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "results/${sample}.vcf.gz"
    done
} > "${TSV}"