#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)
REF=data/ref/chrM.fa
RAW_DIR=data/raw
RESULTS_DIR=results

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

    # Check if final artifacts exist and are up-to-date
    # We check the existence of the final compressed/indexed VCF as the completion marker for the pipeline
    if [[ -f "${TBI}" ]]; then
        continue
    fi

    R1="${RAW_DIR}/${SAMPLE}_1.fq.gz"
    R2="${RAW_DIR}/${SAMPLE}_2.fq.gz"

    # 3 & 4. Alignment and sorting
    # bwa mem with read group, piped to samtools sort
    # Note: The prompt requires literal \t in the RG string for bwa parsing
    RG="@RG\tID:${SAMPLE}\tSM:${SAMPLE}\tLB:${SAMPLE}\tPL:ILLUMINA"

    if [[ ! -f "${BAM}" ]]; then
        bwa mem -t ${THREADS} -R "${RG}" "${REF}" "${R1}" "${R2}" | \
            samtools sort -@ ${THREADS} -o "${BAM}" -
    fi

    # 5. BAM indexing
    if [[ ! -f "${BAI}" ]]; then
        samtools index -@ ${THREADS} "${BAM}"
    fi

    # 6. Variant calling with lofreq
    VCF="${RESULTS_DIR}/${SAMPLE}.vcf"
    if [[ ! -f "${VCF_GZ}" ]]; then
        # Call variants
        lofreq call-parallel --pp-threads ${THREADS} -f "${REF}" -o "${VCF}" "${BAM}"

        # 7. Compress and index VCF
        bgzip -c "${VCF}" > "${VCF_GZ}"
        tabix -p vcf "${VCF_GZ}"

        # Remove intermediate uncompressed VCF
        rm -f "${VCF}"
    fi
done

# 8. Collapse step -> results/collapsed.tsv
COLLAPSED="${RESULTS_DIR}/collapsed.tsv"

# Check if collapsed.tsv needs rebuilding
# It needs rebuilding if it doesn't exist, or if any input VCF.gz is newer than it
NEED_REBUILD=false
if [[ ! -f "${COLLAPSED}" ]]; then
    NEED_REBUILD=true
else
    for SAMPLE in "${SAMPLES[@]}"; do
        VCF_GZ="${RESULTS_DIR}/${SAMPLE}.vcf.gz"
        if [[ "${VCF_GZ}" -nt "${COLLAPSED}" ]]; then
            NEED_REBUILD=true
            break
        fi
    done
fi

if [[ "${NEED_REBUILD}" == true ]]; then
    # Create header
    printf "sample\tchrom\tpos\tref\talt\taf\n" > "${COLLAPSED}"

    # Append data from each sample
    for SAMPLE in "${SAMPLES[@]}"; do
        VCF_GZ="${RESULTS_DIR}/${SAMPLE}.vcf.gz"
        bcftools query -f "${SAMPLE}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "${VCF_GZ}" >> "${COLLAPSED}"
    done
fi