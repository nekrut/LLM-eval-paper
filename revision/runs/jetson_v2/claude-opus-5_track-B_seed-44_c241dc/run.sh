#!/usr/bin/env bash
set -euo pipefail

THREADS="${THREADS:-4}"
REF="data/ref/chrM.fa"
RAW="data/raw"
RES="results"
LOGS="${RES}/logs"

mkdir -p "${RES}" "${LOGS}"

SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)

# ---------- reference indexing ----------
if [ ! -s "${REF}.bwt" ]; then
    bwa index "${REF}" > "${LOGS}/bwa_index.log" 2>&1
fi

if [ ! -s "${REF}.fai" ]; then
    samtools faidx "${REF}"
fi

# ---------- per-sample: map, sort, dedup, index, call ----------
for s in "${SAMPLES[@]}"; do
    r1="${RAW}/${s}_1.fq.gz"
    r2="${RAW}/${s}_2.fq.gz"
    bam="${RES}/${s}.bam"
    bai="${RES}/${s}.bam.bai"
    vcf="${RES}/${s}.vcf.gz"
    tbi="${RES}/${s}.vcf.gz.tbi"

    if [ ! -s "${bam}" ]; then
        bwa mem -t "${THREADS}" \
            -R "@RG\tID:${s}\tSM:${s}\tPL:ILLUMINA\tLB:${s}" \
            "${REF}" "${r1}" "${r2}" 2> "${LOGS}/${s}.bwa.log" \
        | samtools fixmate -m -@ "${THREADS}" - - \
        | samtools sort -@ "${THREADS}" -T "${RES}/${s}.sorttmp" -o "${RES}/${s}.namefix.bam" - 2>> "${LOGS}/${s}.bwa.log"
        samtools markdup -@ "${THREADS}" -T "${RES}/${s}.mdtmp" \
            "${RES}/${s}.namefix.bam" "${RES}/${s}.tmp.bam" 2> "${LOGS}/${s}.markdup.log"
        rm -f "${RES}/${s}.namefix.bam"
        mv "${RES}/${s}.tmp.bam" "${bam}"
    fi

    if [ ! -s "${bai}" ]; then
        samtools index -@ "${THREADS}" "${bam}"
    fi

    if [ ! -s "${RES}/${s}.flagstat.txt" ]; then
        samtools flagstat -@ "${THREADS}" "${bam}" > "${RES}/${s}.flagstat.txt"
    fi

    if [ ! -s "${vcf}" ]; then
        lofreq indelqual --dindel -f "${REF}" -o "${RES}/${s}.iq.bam" "${bam}" \
            > "${LOGS}/${s}.indelqual.log" 2>&1
        samtools index -@ "${THREADS}" "${RES}/${s}.iq.bam"
        lofreq call-parallel --pp-threads "${THREADS}" \
            --call-indels \
            -f "${REF}" \
            -o "${RES}/${s}.raw.vcf" \
            "${RES}/${s}.iq.bam" > "${LOGS}/${s}.lofreq.log" 2>&1
        bcftools sort -T "${RES}/${s}.bcfsort" -Oz -o "${RES}/${s}.tmp.vcf.gz" "${RES}/${s}.raw.vcf" \
            > "${LOGS}/${s}.bcfsort.log" 2>&1
        rm -f "${RES}/${s}.raw.vcf" "${RES}/${s}.iq.bam" "${RES}/${s}.iq.bam.bai"
        mv "${RES}/${s}.tmp.vcf.gz" "${vcf}"
        rm -f "${tbi}"
    fi

    if [ ! -s "${tbi}" ]; then
        tabix -p vcf -f "${vcf}"
    fi
done

# ---------- collapsed table ----------
COLLAPSED="${RES}/collapsed.tsv"
if [ ! -s "${COLLAPSED}" ]; then
    {
        printf 'sample\tchrom\tpos\tref\talt\taf\n'
        for s in "${SAMPLES[@]}"; do
            bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%AF\n' "${RES}/${s}.vcf.gz" \
            | awk -v smp="${s}" 'BEGIN{OFS="\t"}{print smp,$1,$2,$3,$4,$5}'
        done
    } > "${RES}/collapsed.tmp.tsv"
    mv "${RES}/collapsed.tmp.tsv" "${COLLAPSED}"
fi