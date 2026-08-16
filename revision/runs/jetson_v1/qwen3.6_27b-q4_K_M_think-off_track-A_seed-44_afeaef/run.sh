#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)
REF="data/ref/chrM.fa"
RAW_DIR="data/raw"
RESULTS_DIR="results"

mkdir -p "${RESULTS_DIR}"

# 2. Reference indexing (idempotent)
if [[ ! -f "${REF}.fai" ]] || [[ ! -f "${REF}.bwt" ]]; then
    samtools faidx "${REF}"
    bwa index "${REF}"
fi

for SAMPLE in "${SAMPLES[@]}"; do
    BAM="${RESULTS_DIR}/${SAMPLE}.bam"
    BAI="${BAM}.bai"
    VCF_GZ="${RESULTS_DIR}/${SAMPLE}.vcf.gz"
    TBI="${VCF_GZ}.tbi"
    VCF_TMP="${RESULTS_DIR}/${SAMPLE}.vcf"

    # Check if all final artifacts for this sample exist and are up-to-date
    # We check the existence of the final compressed/indexed VCF as the terminal artifact.
    if [[ -f "${TBI}" ]]; then
        continue
    fi

    # 3 & 4. Alignment and sorting
    # bwa mem with read group, piped to samtools sort
    RG="@RG\tID:${SAMPLE}\tSM:${SAMPLE}\tLB:${SAMPLE}\tPL:ILLUMINA"
    
    if [[ ! -f "${BAI}" ]]; then
        bwa mem -t "${THREADS}" -R "${RG}" "${REF}" \
            "${RAW_DIR}/${SAMPLE}_1.fq.gz" \
            "${RAW_DIR}/${SAMPLE}_2.fq.gz" | \
        samtools sort -@ "${THREADS}" -o "${BAM}" -
    fi

    # 5. BAM indexing
    if [[ ! -f "${BAI}" ]]; then
        samtools index -@ "${THREADS}" "${BAM}"
    fi

    # 6. Variant calling with lofreq call-parallel
    # Output to temporary uncompressed VCF
    if [[ ! -f "${VCF_GZ}" ]]; then
        lofreq call-parallel \
            --pp-threads "${THREADS}" \
            -f "${REF}" \
            -o "${VCF_TMP}" \
            "${BAM}"
    fi

    # 7. VCF compression and indexing
    if [[ ! -f "${TBI}" ]]; then
        bgzip -c "${VCF_TMP}" > "${VCF_GZ}"
        tabix -p vcf "${VCF_GZ}"
        rm -f "${VCF_TMP}"
    fi
done

# 8. Collapse step -> results/collapsed.tsv
COLLAPSED_TSV="${RESULTS_DIR}/collapsed.tsv"
NEED_COLLAPSE=false

if [[ ! -f "${COLLAPSED_TSV}" ]]; then
    NEED_COLLAPSE=true
else
    # Check if any VCF is newer than the collapsed TSV
    for SAMPLE in "${SAMPLES[@]}"; do
        VCF_GZ="${RESULTS_DIR}/${SAMPLE}.vcf.gz"
        if [[ "${VCF_GZ}" -nt "${COLLAPSED_TSV}" ]]; then
            NEED_COLLAPSE=true
            break
        fi
    done
fi

if [[ "${NEED_COLLAPSE}" == true ]]; then
    # Create header
    printf "sample\tchrom\tpos\tref\talt\taf\n" > "${COLLAPSED_TSV}"
    
    # Append data from each sample
    for SAMPLE in "${SAMPLES[@]}"; do
        VCF_GZ="${RESULTS_DIR}/${SAMPLE}.vcf.gz"
        bcftools query -f "${SAMPLE}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "${VCF_GZ}" >> "${COLLAPSED_TSV}"
    done
fi