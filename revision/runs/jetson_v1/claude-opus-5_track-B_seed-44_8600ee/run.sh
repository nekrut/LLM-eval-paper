#!/usr/bin/env bash
set -euo pipefail

THREADS="${THREADS:-4}"
RAW_DIR="data/raw"
REF_DIR="data/ref"
REF="${REF_DIR}/chrM.fa"
OUT="results"
LOGS="${OUT}/logs"
TMP="${OUT}/tmp"

SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)

mkdir -p "${OUT}" "${LOGS}" "${TMP}"

# ---------------------------------------------------------------------------
# 1. Reference indices (bwa + samtools faidx)
# ---------------------------------------------------------------------------
if [ ! -s "${REF}.bwt" ]; then
    bwa index "${REF}" >"${LOGS}/bwa_index.log" 2>&1
fi

if [ ! -s "${REF}.fai" ]; then
    samtools faidx "${REF}" >"${LOGS}/faidx.log" 2>&1
fi

# ---------------------------------------------------------------------------
# 2. Per-sample: align -> sort -> markdup -> index -> indelqual -> call
# ---------------------------------------------------------------------------
for s in "${SAMPLES[@]}"; do
    r1="${RAW_DIR}/${s}_1.fq.gz"
    r2="${RAW_DIR}/${s}_2.fq.gz"

    bam="${OUT}/${s}.bam"
    bai="${OUT}/${s}.bam.bai"
    vcf="${OUT}/${s}.vcf.gz"
    tbi="${OUT}/${s}.vcf.gz.tbi"

    # ---- BAM ----
    if [ ! -s "${bam}" ]; then
        bwa mem \
            -t "${THREADS}" \
            -R "@RG\tID:${s}\tSM:${s}\tLB:${s}\tPL:ILLUMINA\tPU:${s}" \
            "${REF}" "${r1}" "${r2}" \
            2>"${LOGS}/${s}.bwa_mem.log" \
        | samtools fixmate -m -@ "${THREADS}" -O bam - "${TMP}/${s}.fixmate.bam" \
            2>"${LOGS}/${s}.fixmate.log"

        samtools sort \
            -@ "${THREADS}" \
            -T "${TMP}/${s}.sort" \
            -o "${TMP}/${s}.sorted.bam" \
            "${TMP}/${s}.fixmate.bam" \
            2>"${LOGS}/${s}.sort.log"

        samtools markdup \
            -@ "${THREADS}" \
            -T "${TMP}/${s}.markdup" \
            "${TMP}/${s}.sorted.bam" \
            "${TMP}/${s}.markdup.bam" \
            2>"${LOGS}/${s}.markdup.log"

        # Add indel qualities so LoFreq can call indels as well as SNVs.
        lofreq indelqual --dindel -f "${REF}" \
            -o "${TMP}/${s}.indelqual.bam" \
            "${TMP}/${s}.markdup.bam" \
            >"${LOGS}/${s}.indelqual.log" 2>&1

        samtools sort \
            -@ "${THREADS}" \
            -T "${TMP}/${s}.sort2" \
            -o "${TMP}/${s}.final.bam" \
            "${TMP}/${s}.indelqual.bam" \
            2>"${LOGS}/${s}.sort2.log"

        mv -f "${TMP}/${s}.final.bam" "${bam}"

        rm -f "${TMP}/${s}.fixmate.bam" "${TMP}/${s}.sorted.bam" \
              "${TMP}/${s}.markdup.bam" "${TMP}/${s}.indelqual.bam"
    fi

    # ---- BAM index ----
    if [ ! -s "${bai}" ]; then
        samtools index -@ "${THREADS}" "${bam}" 2>"${LOGS}/${s}.index.log"
    fi

    # ---- VCF ----
    if [ ! -s "${vcf}" ]; then
        lofreq call-parallel \
            --pp-threads "${THREADS}" \
            -f "${REF}" \
            --call-indels \
            --no-default-filter \
            -o "${TMP}/${s}.raw.vcf" \
            "${bam}" \
            >"${LOGS}/${s}.lofreq_call.log" 2>&1

        lofreq filter \
            -i "${TMP}/${s}.raw.vcf" \
            -o "${TMP}/${s}.filt.vcf" \
            -v 10 -a 0.01 -Q 20 \
            >"${LOGS}/${s}.lofreq_filter.log" 2>&1

        bcftools sort \
            -T "${TMP}/${s}.bcfsort" \
            -Oz -o "${TMP}/${s}.vcf.gz" \
            "${TMP}/${s}.filt.vcf" \
            2>"${LOGS}/${s}.bcftools_sort.log"

        mv -f "${TMP}/${s}.vcf.gz" "${vcf}"
        rm -f "${TMP}/${s}.raw.vcf" "${TMP}/${s}.filt.vcf"
    fi

    # ---- VCF index ----
    if [ ! -s "${tbi}" ]; then
        tabix -p vcf -f "${vcf}" 2>"${LOGS}/${s}.tabix.log"
    fi
done

# ---------------------------------------------------------------------------
# 3. Collapsed table across all samples
# ---------------------------------------------------------------------------
COLLAPSED="${OUT}/collapsed.tsv"

if [ ! -s "${COLLAPSED}" ]; then
    {
        printf 'sample\tchrom\tpos\tref\talt\taf\n'
        for s in "${SAMPLES[@]}"; do
            bcftools query \
                -f "${s}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" \
                "${OUT}/${s}.vcf.gz" \
                2>>"${LOGS}/collapse.log"
        done
    } > "${TMP}/collapsed.tsv.part"

    mv -f "${TMP}/collapsed.tsv.part" "${COLLAPSED}"
fi

rmdir "${TMP}" 2>/dev/null || true