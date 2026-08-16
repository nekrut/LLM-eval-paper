#!/usr/bin/env bash
set -euo pipefail

THREADS="${THREADS:-4}"
RAW_DIR="data/raw"
REF_DIR="data/ref"
REF="${REF_DIR}/chrM.fa"
OUT="results"
LOG="${OUT}/logs"
TMP="${OUT}/tmp"

SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)

mkdir -p "${OUT}" "${LOG}" "${TMP}"

if [ ! -s "${REF}" ]; then
    exit 1
fi

# ---- Reference indices (bwa + samtools faidx) ----
if [ ! -s "${REF}.bwt" ] || [ ! -s "${REF}.sa" ] || [ ! -s "${REF}.pac" ] || [ ! -s "${REF}.ann" ] || [ ! -s "${REF}.amb" ]; then
    bwa index "${REF}" > "${LOG}/bwa_index.log" 2>&1
fi

if [ ! -s "${REF}.fai" ]; then
    samtools faidx "${REF}" > "${LOG}/faidx.log" 2>&1
fi

# ---- Per-sample: align -> sort -> dedup-free indelqual -> index -> call ----
for S in "${SAMPLES[@]}"; do
    R1="${RAW_DIR}/${S}_1.fq.gz"
    R2="${RAW_DIR}/${S}_2.fq.gz"

    if [ ! -s "${R1}" ] || [ ! -s "${R2}" ]; then
        exit 1
    fi

    BAM="${OUT}/${S}.bam"
    BAI="${OUT}/${S}.bam.bai"
    VCF="${OUT}/${S}.vcf.gz"
    TBI="${OUT}/${S}.vcf.gz.tbi"

    # --- BAM ---
    if [ ! -s "${BAM}" ] || [ ! -s "${BAI}" ]; then
        bwa mem \
            -t "${THREADS}" \
            -R "@RG\tID:${S}\tSM:${S}\tPL:ILLUMINA\tLB:${S}" \
            "${REF}" "${R1}" "${R2}" \
            2> "${LOG}/${S}.bwa_mem.log" \
        | samtools fixmate -m -@ "${THREADS}" - - \
            2> "${LOG}/${S}.fixmate.log" \
        | samtools sort -@ "${THREADS}" -T "${TMP}/${S}.sort" -o "${TMP}/${S}.sorted.bam" - \
            2> "${LOG}/${S}.sort.log"

        samtools markdup -@ "${THREADS}" -T "${TMP}/${S}.markdup" \
            "${TMP}/${S}.sorted.bam" "${TMP}/${S}.markdup.bam" \
            > "${LOG}/${S}.markdup.log" 2>&1

        # Add LoFreq indel qualities so indels are callable
        lofreq indelqual --dindel -f "${REF}" \
            -o "${TMP}/${S}.indelqual.bam" "${TMP}/${S}.markdup.bam" \
            > "${LOG}/${S}.indelqual.log" 2>&1

        samtools sort -@ "${THREADS}" -T "${TMP}/${S}.sort2" \
            -o "${TMP}/${S}.final.bam" "${TMP}/${S}.indelqual.bam" \
            2> "${LOG}/${S}.sort2.log"

        mv -f "${TMP}/${S}.final.bam" "${BAM}"
        samtools index -@ "${THREADS}" "${BAM}" > "${LOG}/${S}.index.log" 2>&1

        rm -f "${TMP}/${S}.sorted.bam" "${TMP}/${S}.markdup.bam" "${TMP}/${S}.indelqual.bam"
    fi

    # --- VCF ---
    if [ ! -s "${VCF}" ] || [ ! -s "${TBI}" ]; then
        rm -f "${TMP}/${S}.lofreq.vcf" "${TMP}/${S}.norm.vcf.gz"

        lofreq call-parallel \
            --pp-threads "${THREADS}" \
            --call-indels \
            -f "${REF}" \
            -o "${TMP}/${S}.lofreq.vcf" \
            "${BAM}" \
            > "${LOG}/${S}.lofreq_call.log" 2>&1

        # Normalize (left-align, split multiallelics), add sample column via reheader-free route
        bcftools norm -f "${REF}" -m -any -Ou "${TMP}/${S}.lofreq.vcf" \
            2> "${LOG}/${S}.norm.log" \
        | bcftools sort -T "${TMP}/${S}.bcfsort" -Oz -o "${TMP}/${S}.norm.vcf.gz" - \
            2> "${LOG}/${S}.bcfsort.log"

        mv -f "${TMP}/${S}.norm.vcf.gz" "${VCF}"
        tabix -f -p vcf "${VCF}" > "${LOG}/${S}.tabix.log" 2>&1

        rm -f "${TMP}/${S}.lofreq.vcf"
    fi
done

# ---- Collapsed table ----
COLLAPSED="${OUT}/collapsed.tsv"
if [ ! -s "${COLLAPSED}" ]; then
    : > "${TMP}/collapsed.body.tsv"
    for S in "${SAMPLES[@]}"; do
        bcftools query \
            -f '%CHROM\t%POS\t%REF\t%ALT\t%AF\n' \
            "${OUT}/${S}.vcf.gz" \
            2> "${LOG}/${S}.query.log" \
        | awk -v s="${S}" 'BEGIN{FS=OFS="\t"} {af=$5; if(af=="."||af==""){af="NA"} print s,$1,$2,$3,$4,af}' \
        >> "${TMP}/collapsed.body.tsv"
    done

    {
        printf 'sample\tchrom\tpos\tref\talt\taf\n'
        sort -k1,1 -k3,3n -k4,4 -k5,5 "${TMP}/collapsed.body.tsv"
    } > "${TMP}/collapsed.tsv"

    mv -f "${TMP}/collapsed.tsv" "${COLLAPSED}"
    rm -f "${TMP}/collapsed.body.tsv"
fi

rmdir "${TMP}" 2>/dev/null || true