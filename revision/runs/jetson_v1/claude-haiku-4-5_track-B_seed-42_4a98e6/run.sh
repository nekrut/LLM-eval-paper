#!/usr/bin/env bash
set -euo pipefail

THREADS=4
RESULTS="results"
RAW_DATA="data/raw"
REF_DATA="data/ref"
REF="${REF_DATA}/chrM.fa"

mkdir -p "${RESULTS}"

# Index reference
[[ -f "${REF}.bwt" ]] || bwa index "${REF}"
[[ -f "${REF}.fai" ]] || samtools faidx "${REF}"

# Process samples
for SAMPLE in M117-bl M117-ch M117C1-bl M117C1-ch; do
    R1="${RAW_DATA}/${SAMPLE}_1.fq.gz"
    R2="${RAW_DATA}/${SAMPLE}_2.fq.gz"
    BAM="${RESULTS}/${SAMPLE}.bam"
    BAI="${RESULTS}/${SAMPLE}.bam.bai"
    VCF="${RESULTS}/${SAMPLE}.vcf.gz"
    VCF_TBI="${RESULTS}/${SAMPLE}.vcf.gz.tbi"
    
    # Map reads
    if [[ ! -f "${BAM}" ]]; then
        bwa mem -t "${THREADS}" "${REF}" "${R1}" "${R2}" | \
            samtools sort -@ "${THREADS}" -o "${BAM}" -
    fi
    
    # Index BAM
    if [[ ! -f "${BAI}" ]]; then
        samtools index -@ "${THREADS}" "${BAM}"
    fi
    
    # Call variants
    if [[ ! -f "${VCF}" ]]; then
        VCF_TMP="${RESULTS}/${SAMPLE}.vcf"
        lofreq call -f "${REF}" -o "${VCF_TMP}" "${BAM}"
        bgzip -f "${VCF_TMP}"
    fi
    
    # Index VCF
    if [[ ! -f "${VCF_TBI}" ]]; then
        tabix -p vcf "${VCF}"
    fi
done

# Create collapsed TSV
if [[ ! -f "${RESULTS}/collapsed.tsv" ]]; then
    {
        echo -e "sample\tchrom\tpos\tref\talt\taf"
        for SAMPLE in M117-bl M117-ch M117C1-bl M117C1-ch; do
            VCF="${RESULTS}/${SAMPLE}.vcf.gz"
            if [[ -f "${VCF}" ]]; then
                bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "${VCF}" | while IFS=$'\t' read -r chrom pos ref alt af; do
                    echo -e "${SAMPLE}\t${chrom}\t${pos}\t${ref}\t${alt}\t${af}"
                done
            fi
        done
    } > "${RESULTS}/collapsed.tsv"
fi