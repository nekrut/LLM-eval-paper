#!/usr/bin/env bash
set -euo pipefail

THREADS="${THREADS:-4}"
REF="data/ref/chrM.fa"
RAW="data/raw"
OUT="results"
LOGS="${OUT}/logs"

SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)

mkdir -p "${OUT}" "${LOGS}"

# ---------------------------------------------------------------------------
# 1. Reference indices (bwa + samtools faidx)
# ---------------------------------------------------------------------------
if [[ ! -f "${REF}.bwt" ]]; then
    bwa index "${REF}" >"${LOGS}/bwa_index.log" 2>&1
fi

if [[ ! -f "${REF}.fai" ]]; then
    samtools faidx "${REF}"
fi

# ---------------------------------------------------------------------------
# 2. Per-sample: map -> sort -> markdup -> indelqual -> call -> index
# ---------------------------------------------------------------------------
for S in "${SAMPLES[@]}"; do
    R1="${RAW}/${S}_1.fq.gz"
    R2="${RAW}/${S}_2.fq.gz"

    if [[ ! -f "${OUT}/${S}.bam" || ! -f "${OUT}/${S}.bam.bai" ]]; then
        bwa mem \
            -t "${THREADS}" \
            -R "@RG\tID:${S}\tSM:${S}\tPL:ILLUMINA\tLB:${S}" \
            "${REF}" "${R1}" "${R2}" 2>"${LOGS}/${S}.bwa.log" \
        | samtools fixmate -m -@ "${THREADS}" -u - - \
        | samtools sort -@ "${THREADS}" -u -T "${OUT}/${S}.sorttmp" - \
        | samtools markdup -@ "${THREADS}" -u - - \
        | lofreq indelqual --dindel -f "${REF}" -o "${OUT}/${S}.bam.tmp" - \
            2>"${LOGS}/${S}.indelqual.log"
        mv -f "${OUT}/${S}.bam.tmp" "${OUT}/${S}.bam"
        samtools index -@ "${THREADS}" "${OUT}/${S}.bam"
    fi

    if [[ ! -f "${OUT}/${S}.vcf.gz" || ! -f "${OUT}/${S}.vcf.gz.tbi" ]]; then
        lofreq call \
            --call-indels \
            -f "${REF}" \
            -o "${OUT}/${S}.raw.vcf" \
            "${OUT}/${S}.bam" \
            >"${LOGS}/${S}.lofreq.log" 2>&1
        bcftools sort -T "${OUT}/${S}.bcfsort" -Oz \
            -o "${OUT}/${S}.vcf.gz.tmp" "${OUT}/${S}.raw.vcf" \
            2>"${LOGS}/${S}.bcfsort.log"
        mv -f "${OUT}/${S}.vcf.gz.tmp" "${OUT}/${S}.vcf.gz"
        tabix -p vcf -f "${OUT}/${S}.vcf.gz"
        rm -f "${OUT}/${S}.raw.vcf"
    fi
done

# ---------------------------------------------------------------------------
# 3. Collapsed table across all samples
# ---------------------------------------------------------------------------
if [[ ! -s "${OUT}/collapsed.tsv" ]]; then
    {
        printf 'sample\tchrom\tpos\tref\talt\taf\n'
        for S in "${SAMPLES[@]}"; do
            bcftools query \
                -f "${S}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" \
                "${OUT}/${S}.vcf.gz"
        done
    } > "${OUT}/collapsed.tsv.tmp"
    mv -f "${OUT}/collapsed.tsv.tmp" "${OUT}/collapsed.tsv"
fi

# ---------------------------------------------------------------------------
# 4. Housekeeping: alignment stats + read QC (skipped when already present)
# ---------------------------------------------------------------------------
for S in "${SAMPLES[@]}"; do
    if [[ ! -s "${OUT}/${S}.flagstat.txt" ]]; then
        samtools flagstat -@ "${THREADS}" "${OUT}/${S}.bam" \
            > "${OUT}/${S}.flagstat.txt"
    fi
done

if [[ ! -d "${OUT}/fastqc" ]]; then
    mkdir -p "${OUT}/fastqc"
    fastqc -t "${THREADS}" -q -o "${OUT}/fastqc" \
        "${RAW}"/*_1.fq.gz "${RAW}"/*_2.fq.gz \
        >"${LOGS}/fastqc.log" 2>&1
fi