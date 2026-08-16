#!/usr/bin/env bash
set -euo pipefail

THREADS=4
REF=data/ref/chrM.fa
RESULTS_DIR=results
mkdir -p "${RESULTS_DIR}"

# Index reference if needed
if [ ! -f "${REF}.bwt" ]; then
    bwa index -p "${REF}" "${REF}"
fi
if [ ! -f "${REF}.fai" ]; then
    samtools faidx "${REF}"
fi

samples=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

# Process each sample
for SAMPLE in "${samples[@]}"; do
    BAM="${RESULTS_DIR}/${SAMPLE}.bam"
    BAI="${BAM}.bai"
    VCF="${RESULTS_DIR}/${SAMPLE}.vcf.gz"
    TBI="${VCF}.tbi"

    # Skip if all outputs exist
    if [ -f "${BAM}" ] && [ -f "${BAI}" ] && [ -f "${VCF}" ] && [ -f "${TBI}" ]; then
        continue
    fi

    # Mapping
    bwa mem -t "${THREADS}" "${REF}" "data/raw/${SAMPLE}_1.fq.gz" "data/raw/${SAMPLE}_2.fq.gz" | \
        samtools view -bS - | \
        samtools sort -@ "${THREADS}" -o "${BAM}"
    samtools index "${BAM}"

    # Variant calling
    lofreq call --call-indels -f "${REF}" -i "${BAM}" -o "${VCF}"
    tabix -p vcf "${VCF}"
done

# Generate collapsed table if needed
COLLAPSED="${RESULTS_DIR}/collapsed.tsv"
ALL_VCFS=true
for SAMPLE in "${samples[@]}"; do
    VCF="${RESULTS_DIR}/${SAMPLE}.vcf.gz"
    if [ ! -f "${VCF}" ]; then
        ALL_VCFS=false
        break
    fi
done

if $ALL_VCFS && [ -f "${COLLAPSED}" ]; then
    exit 0
fi

{
    echo -e "sample\tchrom\tpos\tref\talt\taf"
    for SAMPLE in "${samples[@]}"; do
        VCF="${RESULTS_DIR}/${SAMPLE}.vcf.gz"
        bcftools query -f '%CHROM\t%POS\t%REF\t%ALT[\t%AF]\n' "${VCF}" | \
            awk -v s="${SAMPLE}" '{print s"\t"$0}'
    done
} > "${COLLAPSED}"

exit 0