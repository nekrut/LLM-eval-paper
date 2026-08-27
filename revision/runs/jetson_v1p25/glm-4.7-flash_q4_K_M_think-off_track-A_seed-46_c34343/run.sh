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

# 3. Per-sample alignment
for sample in "${SAMPLES[@]}"; do
    fq1="${RAW}/${sample}_1.fq.gz"
    fq2="${RAW}/${sample}_2.fq.gz"
    bam="results/${sample}.bam"
    bai="results/${sample}.bam.bai"
    vcf="results/${sample}.vcf"
    vcfgz="results/${sample}.vcf.gz"
    vcftbi="results/${sample}.vcf.gz.tbi"

    if [[ -f "${vcftbi}" ]]; then
        continue
    fi

    bwa mem -t "${THREADS}" -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" "${fq1}" "${fq2}" \
        | samtools sort -@ "${THREADS}" -o "${bam}"

    samtools index -@ "${THREADS}" "${bam}"

    lofreq call-parallel --pp-threads "${THREADS}" -f "${REF}" -o "${vcf}" "${bam}"

    bgzip -c "${vcf}" > "${vcfgz}"
    tabix -p vcf "${vcfgz}"

    rm "${vcf}"
done

# 8. Collapse step
COLLAPSED="results/collapsed.tsv"
HEADER="sample\tchrom\tpos\tref\talt\taf"

if [[ -f "${COLLAPSED}" ]]; then
    # Check if any input VCF is newer than the TSV
    TSV_MTIME=$(stat -c %Y "${COLLAPSED}" 2>/dev/null || echo 0)
    NEED_REBUILD=0
    for sample in "${SAMPLES[@]}"; do
        vcfgz="results/${sample}.vcf.gz"
        if [[ -f "${vcfgz}" ]]; then
            VCF_MTIME=$(stat -c %Y "${vcfgz}" 2>/dev/null || echo 0)
            if [[ "${VCF_MTIME}" -gt "${TSV_MTIME}" ]]; then
                NEED_REBUILD=1
                break
            fi
        fi
    done
    if [[ "${NEED_REBUILD}" -eq 0 ]]; then
        exit 0
    fi
fi

{
    echo -e "${HEADER}"
    for sample in "${SAMPLES[@]}"; do
        bcftools query -f '{sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "results/${sample}.vcf.gz"
    done
} > "${COLLAPSED}"