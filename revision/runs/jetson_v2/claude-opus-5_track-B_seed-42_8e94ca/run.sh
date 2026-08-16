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

# --- Reference indices (idempotent) -----------------------------------------
if [ ! -s "${REF}.fai" ]; then
    samtools faidx "${REF}" 2> "${LOG}/faidx.log"
fi

if [ ! -s "${REF}.bwt" ] || [ ! -s "${REF}.sa" ] || [ ! -s "${REF}.pac" ] || \
   [ ! -s "${REF}.ann" ] || [ ! -s "${REF}.amb" ]; then
    bwa index "${REF}" 2> "${LOG}/bwa_index.log"
fi

# --- Per-sample: map -> sort -> markdup -> index -> call ---------------------
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
            "${REF}" "${R1}" "${R2}" 2> "${LOG}/${S}.bwa_mem.log" \
        | samtools fixmate -m -@ "${THREADS}" -u - - 2> "${LOG}/${S}.fixmate.log" \
        | samtools sort -@ "${THREADS}" -T "${TMP}/${S}.sort" -u - 2> "${LOG}/${S}.sort.log" \
        | samtools markdup -@ "${THREADS}" -T "${TMP}/${S}.markdup" - "${TMP}/${S}.md.bam" \
            2> "${LOG}/${S}.markdup.log"

        # LoFreq needs indel qualities for indel calling
        samtools index -@ "${THREADS}" "${TMP}/${S}.md.bam" 2> "${LOG}/${S}.index_md.log"
        lofreq indelqual --dindel -f "${REF}" -o "${TMP}/${S}.iq.bam" "${TMP}/${S}.md.bam" \
            2> "${LOG}/${S}.indelqual.log"
        samtools sort -@ "${THREADS}" -T "${TMP}/${S}.iqsort" -o "${TMP}/${S}.final.bam" \
            "${TMP}/${S}.iq.bam" 2> "${LOG}/${S}.iqsort.log"

        mv -f "${TMP}/${S}.final.bam" "${BAM}"
        samtools index -@ "${THREADS}" "${BAM}" 2> "${LOG}/${S}.index.log"
        rm -f "${TMP}/${S}.md.bam" "${TMP}/${S}.md.bam.bai" "${TMP}/${S}.iq.bam"
    fi

    if [ ! -s "${OUT}/${S}.flagstat.txt" ]; then
        samtools flagstat -@ "${THREADS}" "${BAM}" > "${OUT}/${S}.flagstat.txt" \
            2> "${LOG}/${S}.flagstat.log"
    fi

    if [ ! -s "${VCF}" ] || [ ! -s "${TBI}" ]; then
        lofreq call-parallel --pp-threads "${THREADS}" \
            --call-indels \
            -f "${REF}" \
            -o "${TMP}/${S}.lofreq.vcf" \
            "${BAM}" 2> "${LOG}/${S}.lofreq_call.log"

        bcftools sort -T "${TMP}/${S}.bcfsort" -Oz -o "${TMP}/${S}.sorted.vcf.gz" \
            "${TMP}/${S}.lofreq.vcf" 2> "${LOG}/${S}.bcfsort.log"

        # Attach sample name so downstream tables are unambiguous
        printf '%s\n' "${S}" > "${TMP}/${S}.sample.txt"
        bcftools reheader -s "${TMP}/${S}.sample.txt" \
            -o "${TMP}/${S}.rh.vcf.gz" "${TMP}/${S}.sorted.vcf.gz" \
            2> "${LOG}/${S}.reheader.log" || cp -f "${TMP}/${S}.sorted.vcf.gz" "${TMP}/${S}.rh.vcf.gz"

        mv -f "${TMP}/${S}.rh.vcf.gz" "${VCF}"
        tabix -f -p vcf "${VCF}" 2> "${LOG}/${S}.tabix.log"
        rm -f "${TMP}/${S}.lofreq.vcf" "${TMP}/${S}.sorted.vcf.gz" "${TMP}/${S}.sample.txt"
    fi
done

# --- Collapsed table ---------------------------------------------------------
if [ ! -s "${OUT}/collapsed.tsv" ]; then
    {
        printf 'sample\tchrom\tpos\tref\talt\taf\n'
        for S in "${SAMPLES[@]}"; do
            bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "${OUT}/${S}.vcf.gz" \
                2> "${LOG}/${S}.query.log" \
            | awk -v s="${S}" 'BEGIN{FS=OFS="\t"} {print s,$1,$2,$3,$4,$5}'
        done
    } > "${TMP}/collapsed.tsv.part"
    mv -f "${TMP}/collapsed.tsv.part" "${OUT}/collapsed.tsv"
fi

rmdir "${TMP}" 2>/dev/null || true