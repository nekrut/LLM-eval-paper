#!/usr/bin/env bash
set -euo pipefail

THREADS="${THREADS:-4}"
REF="data/ref/chrM.fa"
RAW="data/raw"
RES="results"
LOG="${RES}/logs"

SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)

mkdir -p "${RES}" "${LOG}" "${RES}/tmp"

# ---------------------------------------------------------------------------
# 1. Reference indices (bwa + samtools faidx), built once, idempotent.
# ---------------------------------------------------------------------------
if [ ! -s "${REF}.bwt" ]; then
    bwa index "${REF}" 2> "${LOG}/bwa_index.log"
fi

if [ ! -s "${REF}.fai" ]; then
    samtools faidx "${REF}" 2> "${LOG}/faidx.log"
fi

# ---------------------------------------------------------------------------
# 2. Per-sample: map -> sort -> markdup -> indelqual -> index -> call -> index
# ---------------------------------------------------------------------------
for S in "${SAMPLES[@]}"; do
    R1="${RAW}/${S}_1.fq.gz"
    R2="${RAW}/${S}_2.fq.gz"
    BAM="${RES}/${S}.bam"
    BAI="${RES}/${S}.bam.bai"
    VCF="${RES}/${S}.vcf.gz"
    TBI="${RES}/${S}.vcf.gz.tbi"
    TMP="${RES}/tmp/${S}"

    mkdir -p "${TMP}"

    if [ ! -s "${BAM}" ] || [ ! -s "${BAI}" ]; then
        bwa mem \
            -t "${THREADS}" \
            -R "@RG\tID:${S}\tSM:${S}\tLB:${S}\tPL:ILLUMINA\tPU:${S}" \
            "${REF}" "${R1}" "${R2}" 2> "${LOG}/${S}.bwa_mem.log" \
        | samtools fixmate -@ "${THREADS}" -m -u - - 2> "${LOG}/${S}.fixmate.log" \
        | samtools sort -@ "${THREADS}" -T "${TMP}/sort" -u - 2> "${LOG}/${S}.sort.log" \
        | samtools markdup -@ "${THREADS}" -T "${TMP}/markdup" - "${TMP}/md.bam" \
            2> "${LOG}/${S}.markdup.log"

        # LoFreq needs indel qualities for indel calling; keeps SNV calls unchanged.
        lofreq indelqual --dindel -f "${REF}" -o "${TMP}/iq.bam" "${TMP}/md.bam" \
            2> "${LOG}/${S}.indelqual.log"

        samtools sort -@ "${THREADS}" -T "${TMP}/sort2" -o "${TMP}/final.bam" "${TMP}/iq.bam" \
            2> "${LOG}/${S}.sort2.log"

        mv -f "${TMP}/final.bam" "${BAM}"
        rm -f "${TMP}/md.bam" "${TMP}/iq.bam"

        samtools index -@ "${THREADS}" "${BAM}" 2> "${LOG}/${S}.index.log"
    fi

    if [ ! -s "${BAI}" ]; then
        samtools index -@ "${THREADS}" "${BAM}" 2> "${LOG}/${S}.index.log"
    fi

    if [ ! -s "${VCF}" ] || [ ! -s "${TBI}" ]; then
        lofreq call-parallel \
            --pp-threads "${THREADS}" \
            --call-indels \
            -f "${REF}" \
            -o "${TMP}/raw.vcf" \
            "${BAM}" 2> "${LOG}/${S}.lofreq_call.log"

        bcftools sort -T "${TMP}/bcfsort" -Oz -o "${TMP}/sorted.vcf.gz" "${TMP}/raw.vcf" \
            2> "${LOG}/${S}.bcftools_sort.log"

        # Normalise (left-align, split multiallelics) against the reference.
        bcftools norm -f "${REF}" -m -any -Oz -o "${TMP}/norm.vcf.gz" "${TMP}/sorted.vcf.gz" \
            2> "${LOG}/${S}.bcftools_norm.log"

        mv -f "${TMP}/norm.vcf.gz" "${VCF}"
        rm -f "${TMP}/raw.vcf" "${TMP}/sorted.vcf.gz"

        tabix -f -p vcf "${VCF}" 2> "${LOG}/${S}.tabix.log"
    fi

    if [ ! -s "${TBI}" ]; then
        tabix -f -p vcf "${VCF}" 2> "${LOG}/${S}.tabix.log"
    fi

    rmdir "${TMP}" 2>/dev/null || true
done

# ---------------------------------------------------------------------------
# 3. Collapse every per-sample VCF into one long table.
# ---------------------------------------------------------------------------
COLLAPSED="${RES}/collapsed.tsv"

if [ ! -s "${COLLAPSED}" ]; then
    TMPTSV="${RES}/tmp/collapsed.partial.tsv"
    : > "${TMPTSV}"

    for S in "${SAMPLES[@]}"; do
        bcftools query \
            -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' \
            "${RES}/${S}.vcf.gz" 2> "${LOG}/${S}.query.log" \
        | awk -v OFS='\t' -v smp="${S}" '
            {
                af = $5
                if (af == "" || af == ".") af = "NA"
                print smp, $1, $2, $3, $4, af
            }' >> "${TMPTSV}"
    done

    {
        printf 'sample\tchrom\tpos\tref\talt\taf\n'
        sort -k1,1 -k2,2 -k3,3n -k4,4 -k5,5 "${TMPTSV}"
    } > "${COLLAPSED}"

    rm -f "${TMPTSV}"
fi

rmdir "${RES}/tmp" 2>/dev/null || true