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

# ---------------------------------------------------------------------------
# 1. Reference indices (samtools faidx + bwa index)
# ---------------------------------------------------------------------------
if [ ! -s "${REF}.fai" ]; then
    samtools faidx "${REF}" 2> "${LOG}/faidx.log"
fi

if [ ! -s "${REF}.bwt" ] || [ ! -s "${REF}.sa" ] || [ ! -s "${REF}.pac" ] || \
   [ ! -s "${REF}.ann" ] || [ ! -s "${REF}.amb" ]; then
    bwa index "${REF}" > "${LOG}/bwa_index.log" 2>&1
fi

# ---------------------------------------------------------------------------
# 2. Per-sample: map -> sort -> markdup-free dedup-free BAM -> index
#    then LoFreq indel qualities + variant calling -> bgzipped VCF + tbi
# ---------------------------------------------------------------------------
for S in "${SAMPLES[@]}"; do
    R1="${RAW_DIR}/${S}_1.fq.gz"
    R2="${RAW_DIR}/${S}_2.fq.gz"
    BAM="${OUT}/${S}.bam"
    BAI="${OUT}/${S}.bam.bai"
    VCF="${OUT}/${S}.vcf.gz"
    TBI="${OUT}/${S}.vcf.gz.tbi"

    if [ ! -s "${BAM}" ] || [ ! -s "${BAI}" ]; then
        bwa mem -t "${THREADS}" \
            -R "@RG\tID:${S}\tSM:${S}\tPL:ILLUMINA\tLB:${S}" \
            "${REF}" "${R1}" "${R2}" 2> "${LOG}/${S}.bwa.log" \
        | samtools fixmate -m -@ "${THREADS}" - - 2> "${LOG}/${S}.fixmate.log" \
        | samtools sort -@ "${THREADS}" -T "${TMP}/${S}.sort" \
            -o "${TMP}/${S}.pos.bam" - 2> "${LOG}/${S}.sort.log"

        samtools markdup -@ "${THREADS}" -T "${TMP}/${S}.markdup" \
            "${TMP}/${S}.pos.bam" "${TMP}/${S}.md.bam" 2> "${LOG}/${S}.markdup.log"

        lofreq indelqual --dindel -f "${REF}" \
            -o "${TMP}/${S}.iq.bam" "${TMP}/${S}.md.bam" 2> "${LOG}/${S}.indelqual.log"

        samtools sort -@ "${THREADS}" -T "${TMP}/${S}.sort2" \
            -o "${TMP}/${S}.final.bam" "${TMP}/${S}.iq.bam" 2> "${LOG}/${S}.sort2.log"

        mv -f "${TMP}/${S}.final.bam" "${BAM}"
        samtools index -@ "${THREADS}" "${BAM}" 2> "${LOG}/${S}.index.log"
        rm -f "${TMP}/${S}.pos.bam" "${TMP}/${S}.md.bam" "${TMP}/${S}.iq.bam"
    fi

    if [ ! -s "${VCF}" ] || [ ! -s "${TBI}" ]; then
        lofreq call --call-indels -f "${REF}" \
            -o "${TMP}/${S}.raw.vcf" "${BAM}" 2> "${LOG}/${S}.lofreq_call.log"

        bcftools sort -T "${TMP}/${S}.bcfsort" -Oz \
            -o "${TMP}/${S}.vcf.gz" "${TMP}/${S}.raw.vcf" 2> "${LOG}/${S}.bcfsort.log"

        mv -f "${TMP}/${S}.vcf.gz" "${VCF}"
        tabix -f -p vcf "${VCF}" 2> "${LOG}/${S}.tabix.log"
        rm -f "${TMP}/${S}.raw.vcf"
    fi
done

# ---------------------------------------------------------------------------
# 3. Collapse all per-sample VCFs into one tidy table
# ---------------------------------------------------------------------------
COLLAPSED="${OUT}/collapsed.tsv"
if [ ! -s "${COLLAPSED}" ]; then
    {
        printf 'sample\tchrom\tpos\tref\talt\taf\n'
        for S in "${SAMPLES[@]}"; do
            bcftools query \
                -f "${S}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" \
                "${OUT}/${S}.vcf.gz" 2>> "${LOG}/collapse.log"
        done
    } > "${TMP}/collapsed.tsv.part"
    mv -f "${TMP}/collapsed.tsv.part" "${COLLAPSED}"
fi

rmdir "${TMP}" 2>/dev/null || true