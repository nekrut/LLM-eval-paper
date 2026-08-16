#!/usr/bin/env bash
set -euo pipefail

THREADS="${THREADS:-4}"

RAW_DIR="data/raw"
REF_DIR="data/ref"
REF="${REF_DIR}/chrM.fa"
RES="results"
LOG="${RES}/logs"

mkdir -p "${RES}" "${LOG}"

SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)

# ---------------------------------------------------------------
# 1. Reference indexes (bwa + faidx)
# ---------------------------------------------------------------
if [ ! -s "${REF}.fai" ]; then
    samtools faidx "${REF}"
fi

if [ ! -s "${REF}.bwt" ]; then
    bwa index "${REF}" >"${LOG}/bwa_index.log" 2>&1
fi

# ---------------------------------------------------------------
# 2. Per-sample: QC, map, sort, dedup, indel-qual, call, index
# ---------------------------------------------------------------
mkdir -p "${RES}/fastqc"

for S in "${SAMPLES[@]}"; do
    R1="${RAW_DIR}/${S}_1.fq.gz"
    R2="${RAW_DIR}/${S}_2.fq.gz"

    # --- FastQC (optional QC artifact; skipped if already produced) ---
    if [ ! -s "${RES}/fastqc/${S}_1_fastqc.zip" ] || [ ! -s "${RES}/fastqc/${S}_2_fastqc.zip" ]; then
        fastqc -t "${THREADS}" -q -o "${RES}/fastqc" "${R1}" "${R2}" >"${LOG}/${S}.fastqc.log" 2>&1
    fi

    # --- Alignment -> coordinate-sorted, duplicate-marked/removed BAM ---
    if [ ! -s "${RES}/${S}.bam" ]; then
        bwa mem -t "${THREADS}" \
            -R "@RG\tID:${S}\tSM:${S}\tLB:${S}\tPL:ILLUMINA\tPU:${S}" \
            "${REF}" "${R1}" "${R2}" 2>"${LOG}/${S}.bwa.log" \
        | samtools fixmate -m -@ "${THREADS}" -O bam - "${RES}/${S}.fixmate.tmp.bam" \
            2>"${LOG}/${S}.fixmate.log"

        samtools sort -@ "${THREADS}" -o "${RES}/${S}.sorted.tmp.bam" \
            "${RES}/${S}.fixmate.tmp.bam" 2>"${LOG}/${S}.sort.log"
        rm -f "${RES}/${S}.fixmate.tmp.bam"

        samtools markdup -r -@ "${THREADS}" \
            -f "${LOG}/${S}.markdup.stats.txt" \
            "${RES}/${S}.sorted.tmp.bam" "${RES}/${S}.dedup.tmp.bam" \
            2>"${LOG}/${S}.markdup.log"
        rm -f "${RES}/${S}.sorted.tmp.bam"

        # LoFreq indel qualities (Dindel) so indels can be called downstream
        lofreq indelqual --dindel -f "${REF}" \
            -o "${RES}/${S}.iq.tmp.bam" "${RES}/${S}.dedup.tmp.bam" \
            >"${LOG}/${S}.indelqual.log" 2>&1
        rm -f "${RES}/${S}.dedup.tmp.bam"

        mv "${RES}/${S}.iq.tmp.bam" "${RES}/${S}.bam"
        rm -f "${RES}/${S}.bam.bai"
    fi

    if [ ! -s "${RES}/${S}.bam.bai" ]; then
        samtools index -@ "${THREADS}" "${RES}/${S}.bam"
    fi

    # --- Basic alignment stats ---
    if [ ! -s "${RES}/${S}.flagstat.txt" ]; then
        samtools flagstat -@ "${THREADS}" "${RES}/${S}.bam" >"${RES}/${S}.flagstat.txt"
    fi
    if [ ! -s "${RES}/${S}.idxstats.txt" ]; then
        samtools idxstats "${RES}/${S}.bam" >"${RES}/${S}.idxstats.txt"
    fi

    # --- Variant calling (LoFreq: low-frequency aware, reports AF) ---
    if [ ! -s "${RES}/${S}.vcf.gz" ]; then
        lofreq call-parallel --pp-threads "${THREADS}" \
            --call-indels \
            -f "${REF}" \
            -o "${RES}/${S}.lofreq.tmp.vcf" \
            "${RES}/${S}.bam" >"${LOG}/${S}.lofreq.log" 2>&1

        bcftools sort -O z -o "${RES}/${S}.vcf.tmp.gz" \
            "${RES}/${S}.lofreq.tmp.vcf" 2>"${LOG}/${S}.bcftools_sort.log"
        rm -f "${RES}/${S}.lofreq.tmp.vcf"

        mv "${RES}/${S}.vcf.tmp.gz" "${RES}/${S}.vcf.gz"
        rm -f "${RES}/${S}.vcf.gz.tbi"
    fi

    if [ ! -s "${RES}/${S}.vcf.gz.tbi" ]; then
        tabix -p vcf "${RES}/${S}.vcf.gz"
    fi
done

# ---------------------------------------------------------------
# 3. Collapsed table across all samples
# ---------------------------------------------------------------
if [ ! -s "${RES}/collapsed.tsv" ]; then
    {
        printf 'sample\tchrom\tpos\tref\talt\taf\n'
        for S in "${SAMPLES[@]}"; do
            bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "${RES}/${S}.vcf.gz" 2>/dev/null \
                || bcftools view -H "${RES}/${S}.vcf.gz" \
                   | awk 'BEGIN{FS=OFS="\t"}
                          {
                            af="NA";
                            n=split($8,kv,";");
                            for(i=1;i<=n;i++){ if(kv[i]~/^AF=/){ af=substr(kv[i],4) } }
                            print $1,$2,$4,$5,af
                          }'
        done > "${RES}/collapsed.body.tmp"
        cat "${RES}/collapsed.body.tmp"
    } > "${RES}/collapsed.tsv.tmp" 2>/dev/null || true
    rm -f "${RES}/collapsed.body.tmp"

    # Rebuild deterministically with sample column prefixed
    {
        printf 'sample\tchrom\tpos\tref\talt\taf\n'
        for S in "${SAMPLES[@]}"; do
            bcftools view -H "${RES}/${S}.vcf.gz" \
            | awk -v s="${S}" 'BEGIN{FS=OFS="\t"}
                   {
                     af="NA";
                     n=split($8,kv,";");
                     for(i=1;i<=n;i++){ if(kv[i]~/^AF=/){ af=substr(kv[i],4) } }
                     print s,$1,$2,$4,$5,af
                   }'
        done
    } > "${RES}/collapsed.tsv.tmp2"

    mv "${RES}/collapsed.tsv.tmp2" "${RES}/collapsed.tsv"
    rm -f "${RES}/collapsed.tsv.tmp"
fi