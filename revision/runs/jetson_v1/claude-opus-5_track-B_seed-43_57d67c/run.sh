#!/usr/bin/env bash
set -euo pipefail

THREADS="${THREADS:-4}"
RAW_DIR="data/raw"
REF_DIR="data/ref"
REF="${REF_DIR}/chrM.fa"
OUT="results"
LOG="${OUT}/logs"
WORK="${OUT}/work"

SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)

mkdir -p "${OUT}" "${LOG}" "${WORK}"

if [ ! -s "${REF}" ]; then
    printf 'missing reference: %s\n' "${REF}" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# 1. Reference indices (bwa + faidx). Built once, reused on rerun.
# ---------------------------------------------------------------------------
if [ ! -s "${REF}.fai" ]; then
    samtools faidx "${REF}"
fi

if [ ! -s "${REF}.bwt" ] || [ ! -s "${REF}.sa" ] || [ ! -s "${REF}.pac" ] || [ ! -s "${REF}.ann" ] || [ ! -s "${REF}.amb" ]; then
    bwa index "${REF}" >"${LOG}/bwa_index.log" 2>&1
fi

CHROM="$(cut -f1 "${REF}.fai" | head -n 1)"

# ---------------------------------------------------------------------------
# 2. Per-sample: map -> sort -> markdup -> indelqual -> call -> index
# ---------------------------------------------------------------------------
for S in "${SAMPLES[@]}"; do
    R1="${RAW_DIR}/${S}_1.fq.gz"
    R2="${RAW_DIR}/${S}_2.fq.gz"

    if [ ! -s "${R1}" ] || [ ! -s "${R2}" ]; then
        printf 'missing FASTQ pair for sample %s\n' "${S}" >&2
        exit 1
    fi

    BAM="${OUT}/${S}.bam"
    BAI="${OUT}/${S}.bam.bai"
    VCF="${OUT}/${S}.vcf.gz"
    TBI="${OUT}/${S}.vcf.gz.tbi"

    # --- alignment ---------------------------------------------------------
    if [ ! -s "${BAM}" ] || [ ! -s "${BAI}" ]; then
        bwa mem \
            -t "${THREADS}" \
            -R "@RG\tID:${S}\tSM:${S}\tLB:${S}\tPL:ILLUMINA\tPU:${S}" \
            "${REF}" "${R1}" "${R2}" \
            2>"${LOG}/${S}.bwa_mem.log" \
        | samtools fixmate -m -@ "${THREADS}" -O bam - "${WORK}/${S}.fixmate.bam" \
            2>"${LOG}/${S}.fixmate.log"

        samtools sort -@ "${THREADS}" -T "${WORK}/${S}.sorttmp" \
            -o "${WORK}/${S}.sorted.bam" "${WORK}/${S}.fixmate.bam" \
            2>"${LOG}/${S}.sort.log"

        samtools markdup -@ "${THREADS}" -T "${WORK}/${S}.mdtmp" \
            "${WORK}/${S}.sorted.bam" "${WORK}/${S}.markdup.bam" \
            2>"${LOG}/${S}.markdup.log"

        # LoFreq needs base-quality-style indel qualities to call indels.
        lofreq indelqual --dindel -f "${REF}" \
            -o "${WORK}/${S}.indelqual.bam" "${WORK}/${S}.markdup.bam" \
            2>"${LOG}/${S}.indelqual.log"

        samtools sort -@ "${THREADS}" -T "${WORK}/${S}.sorttmp2" \
            -o "${WORK}/${S}.final.bam" "${WORK}/${S}.indelqual.bam" \
            2>"${LOG}/${S}.sort2.log"

        mv -f "${WORK}/${S}.final.bam" "${BAM}"
        samtools index -@ "${THREADS}" "${BAM}"

        rm -f "${WORK}/${S}.fixmate.bam" "${WORK}/${S}.sorted.bam" \
              "${WORK}/${S}.markdup.bam" "${WORK}/${S}.indelqual.bam"
    fi

    # --- variant calling ---------------------------------------------------
    if [ ! -s "${VCF}" ] || [ ! -s "${TBI}" ]; then
        lofreq call-parallel \
            --pp-threads "${THREADS}" \
            --call-indels \
            --no-default-filter \
            -f "${REF}" \
            -o "${WORK}/${S}.lofreq.vcf" \
            "${BAM}" \
            >"${LOG}/${S}.lofreq_call.log" 2>&1

        lofreq filter \
            -i "${WORK}/${S}.lofreq.vcf" \
            -o "${WORK}/${S}.filt.vcf" \
            -v 10 -a 0.01 -Q 30 \
            >"${LOG}/${S}.lofreq_filter.log" 2>&1

        # Normalise, left-align, split multi-allelics, add sample name.
        printf '%s\n' "${S}" > "${WORK}/${S}.sample.txt"
        bcftools norm -f "${REF}" -m -any -Ou "${WORK}/${S}.filt.vcf" \
            2>"${LOG}/${S}.norm.log" \
        | bcftools sort -T "${WORK}/${S}.bcfsort" -Oz -o "${WORK}/${S}.vcf.gz" \
            2>"${LOG}/${S}.bcfsort.log"

        mv -f "${WORK}/${S}.vcf.gz" "${VCF}"
        tabix -f -p vcf "${VCF}"

        rm -f "${WORK}/${S}.lofreq.vcf" "${WORK}/${S}.filt.vcf" "${WORK}/${S}.sample.txt"
    fi
done

# ---------------------------------------------------------------------------
# 3. Collapsed table across all samples
# ---------------------------------------------------------------------------
COLLAPSED="${OUT}/collapsed.tsv"
if [ ! -s "${COLLAPSED}" ]; then
    TMP_TSV="${WORK}/collapsed.partial.tsv"
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "${TMP_TSV}"
    for S in "${SAMPLES[@]}"; do
        bcftools query \
            -f "${S}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" \
            "${OUT}/${S}.vcf.gz" >> "${TMP_TSV}" \
            2>"${LOG}/${S}.query.log"
    done
    mv -f "${TMP_TSV}" "${COLLAPSED}"
fi

# ---------------------------------------------------------------------------
# 4. Reference sanity check (chrM length) recorded once
# ---------------------------------------------------------------------------
if [ ! -s "${OUT}/reference_stats.tsv" ]; then
    { printf 'chrom\tlength\n'; cut -f1,2 "${REF}.fai"; } > "${WORK}/reference_stats.tsv"
    mv -f "${WORK}/reference_stats.tsv" "${OUT}/reference_stats.tsv"
fi

# ---------------------------------------------------------------------------
# 5. Per-sample alignment summary (idempotent, cheap)
# ---------------------------------------------------------------------------
for S in "${SAMPLES[@]}"; do
    if [ ! -s "${OUT}/${S}.flagstat.txt" ]; then
        samtools flagstat -@ "${THREADS}" "${OUT}/${S}.bam" \
            > "${WORK}/${S}.flagstat.txt" 2>"${LOG}/${S}.flagstat.log"
        mv -f "${WORK}/${S}.flagstat.txt" "${OUT}/${S}.flagstat.txt"
    fi
done

: "${CHROM}"