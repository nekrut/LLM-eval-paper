#!/usr/bin/env bash
set -euo pipefail

mkdir -p results

SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
THREADS=${THREADS:-4}
REF="data/ref/chrM.fa"

# Index reference
if [[ ! -f "${REF}.bwt" ]]; then
    bwa index "${REF}"
fi

if [[ ! -f "${REF}.fai" ]]; then
    samtools faidx "${REF}"
fi

# Align, sort, and index BAM for each sample
for SAMPLE in "${SAMPLES[@]}"; do
    BAM="results/${SAMPLE}.bam"
    BAI="${BAM}.bai"
    
    if [[ -f "${BAI}" ]]; then
        continue
    fi
    
    R1="data/raw/${SAMPLE}_1.fq.gz"
    R2="data/raw/${SAMPLE}_2.fq.gz"
    
    bwa mem -t ${THREADS} "${REF}" "${R1}" "${R2}" | \
        samtools sort -@ ${THREADS} -o "${BAM}" -
    
    samtools index -@ ${THREADS} "${BAM}"
done

# Call variants and create VCF for each sample
for SAMPLE in "${SAMPLES[@]}"; do
    BAM="results/${SAMPLE}.bam"
    VCF="results/${SAMPLE}.vcf"
    VCF_GZ="results/${SAMPLE}.vcf.gz"
    VCF_TBI="${VCF_GZ}.tbi"
    
    if [[ -f "${VCF_TBI}" ]]; then
        continue
    fi
    
    lofreq call -f "${REF}" -o "${VCF}" "${BAM}"
    bgzip -f "${VCF}"
    tabix -p vcf "${VCF_GZ}"
done

# Create collapsed TSV
COLLAPSED="results/collapsed.tsv"
if [[ ! -f "${COLLAPSED}" ]]; then
    echo -e "sample\tchrom\tpos\tref\talt\taf" > "${COLLAPSED}"
    
    for SAMPLE in "${SAMPLES[@]}"; do
        VCF_GZ="results/${SAMPLE}.vcf.gz"
        bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "${VCF_GZ}" | \
        awk -v sample="${SAMPLE}" '{print sample "\t" $0}' >> "${COLLAPSED}"
    done
fi