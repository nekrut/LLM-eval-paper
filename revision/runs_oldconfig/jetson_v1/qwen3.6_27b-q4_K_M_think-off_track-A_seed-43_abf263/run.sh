#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)
REF="data/ref/chrM.fa"
RAW_DIR="data/raw"
RESULTS_DIR="results"

mkdir -p "${RESULTS_DIR}"

# 2. Reference indexing (once, in data/ref/)
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
    # We check the newest artifact (TBI) against the BAM and VCF inputs.
    # If TBI exists, we assume the pipeline is complete for this sample.
    if [[ -f "${TBI}" ]]; then
        continue
    fi

    R1="${RAW_DIR}/${SAMPLE}_1.fq.gz"
    R2="${RAW_DIR}/${SAMPLE}_2.fq.gz"

    # 3 & 4. Alignment and sorting
    # Idempotency: if BAM exists, skip alignment
    if [[ ! -f "${BAM}" ]]; then
        bwa mem -t "${THREADS}" \
            -R "@RG\tID:${SAMPLE}\tSM:${SAMPLE}\tLB:${SAMPLE}\tPL:ILLUMINA" \
            "${REF}" "${R1}" "${R2}" | \
        samtools sort -@ "${THREADS}" -o "${BAM}" -
    fi

    # 5. BAM indexing
    if [[ ! -f "${BAI}" ]]; then
        samtools index -@ "${THREADS}" "${BAM}"
    fi

    # 6. Variant calling with lofreq call-parallel
    # Idempotency: if VCF_GZ exists, skip calling and compression
    if [[ ! -f "${VCF_GZ}" ]]; then
        lofreq call-parallel \
            --pp-threads "${THREADS}" \
            -f "${REF}" \
            -o "${VCF_TMP}" \
            "${BAM}"

        # 7. VCF compression and indexing
        bgzip -c "${VCF_TMP}" > "${VCF_GZ}"
        tabix -p vcf "${VCF_GZ}"
        rm -f "${VCF_TMP}"
    fi
done

# 8. Collapse step -> results/collapsed.tsv
COLLAPSED_TSV="${RESULTS_DIR}/collapsed.tsv"
NEED_REBUILD=false

if [[ ! -f "${COLLAPSED_TSV}" ]]; then
    NEED_REBUILD=true
else
    # Check if any VCF is newer than the collapsed TSV
    for SAMPLE in "${SAMPLES[@]}"; do
        VCF_GZ="${RESULTS_DIR}/${SAMPLE}.vcf.gz"
        if [[ "${VCF_GZ}" -nt "${COLLAPSED_TSV}" ]]; then
            NEED_REBUILD=true
            break
        fi
    done
fi

if [[ "${NEED_REBUILD}" == true ]]; then
    {
        printf "sample\tchrom\tpos\tref\talt\taf\n"
        for SAMPLE in "${SAMPLES[@]}"; do
            VCF_GZ="${RESULTS_DIR}/${SAMPLE}.vcf.gz"
            bcftools query -f "${SAMPLE}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "${VCF_GZ}"
        done
    } > "${COLLAPSED_TSV}"
fi