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
# 1. Reference indices (bwa + faidx). Built once; skipped if already present.
# ---------------------------------------------------------------------------
if [ ! -s "${REF}.fai" ]; then
    samtools faidx "${REF}" 2> "${LOGS}/faidx.log"
fi

if [ ! -s "${REF}.bwt" ] || [ ! -s "${REF}.sa" ] || [ ! -s "${REF}.pac" ] || \
   [ ! -s "${REF}.ann" ] || [ ! -s "${REF}.amb" ]; then
    bwa index "${REF}" 2> "${LOGS}/bwa_index.log"
fi

# ---------------------------------------------------------------------------
# 2. Per-sample: align -> sort -> mark duplicates -> indel-qual -> index -> call
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
            "${REF}" "${R1}" "${R2}" 2> "${LOGS}/${S}.bwa_mem.log" \
        | samtools fixmate -m -@ "${THREADS}" -u - - 2> "${LOGS}/${S}.fixmate.log" \
        | samtools sort -@ "${THREADS}" -T "${TMP}/${S}.sort" -u - 2> "${LOGS}/${S}.sort.log" \
        | samtools markdup -@ "${THREADS}" -T "${TMP}/${S}.markdup" - "${TMP}/${S}.md.bam" \
            2> "${LOGS}/${S}.markdup.log"

        # LoFreq indel qualities enable indel calling in the same pass.
        lofreq indelqual --dindel -f "${REF}" -o "${TMP}/${S}.idq.bam" "${TMP}/${S}.md.bam" \
            2> "${LOGS}/${S}.indelqual.log"

        samtools sort -@ "${THREADS}" -T "${TMP}/${S}.sort2" \
            -o "${TMP}/${S}.final.bam" "${TMP}/${S}.idq.bam" 2> "${LOGS}/${S}.sort2.log"

        mv -f "${TMP}/${S}.final.bam" "${BAM}"
        samtools index -@ "${THREADS}" "${BAM}" 2> "${LOGS}/${S}.index.log"
        rm -f "${TMP}/${S}.md.bam" "${TMP}/${S}.idq.bam"

        samtools flagstat -@ "${THREADS}" "${BAM}" > "${LOGS}/${S}.flagstat.txt"
    fi

    if [ ! -s "${VCF}" ] || [ ! -s "${TBI}" ]; then
        lofreq call-parallel --pp-threads "${THREADS}" \
            --call-indels \
            -f "${REF}" \
            -o "${TMP}/${S}.lofreq.vcf" \
            "${BAM}" 2> "${LOGS}/${S}.lofreq_call.log"

        bcftools view -Oz -o "${TMP}/${S}.vcf.gz" "${TMP}/${S}.lofreq.vcf" \
            2> "${LOGS}/${S}.bcftools_view.log"
        mv -f "${TMP}/${S}.vcf.gz" "${VCF}"
        tabix -f -p vcf "${VCF}" 2> "${LOGS}/${S}.tabix.log"
        rm -f "${TMP}/${S}.lofreq.vcf"
    fi
done

# ---------------------------------------------------------------------------
# 3. Collapsed table: sample / chrom / pos / ref / alt / af
# ---------------------------------------------------------------------------
COLLAPSED="${OUT}/collapsed.tsv"
if [ ! -s "${COLLAPSED}" ]; then
    {
        printf 'sample\tchrom\tpos\tref\talt\taf\n'
        for S in "${SAMPLES[@]}"; do
            bcftools query \
                -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' \
                "${OUT}/${S}.vcf.gz" \
            | awk -v s="${S}" 'BEGIN{FS=OFS="\t"} {print s,$1,$2,$3,$4,$5}'
        done
    } > "${TMP}/collapsed.tsv.part"
    mv -f "${TMP}/collapsed.tsv.part" "${COLLAPSED}"
fi

rmdir "${TMP}" 2>/dev/null || true