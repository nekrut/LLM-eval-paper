#!/usr/bin/env bash
set -euo pipefail

THREADS=4
REF="data/ref/chrM.fa"
RAWDIR="data/raw"
OUTDIR="results"

mkdir -p "${OUTDIR}"

SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)

# --- reference indexing (idempotent) ---
if [ ! -s "${REF}.bwt" ]; then
    bwa index "${REF}"
fi
if [ ! -s "${REF}.fai" ]; then
    samtools faidx "${REF}"
fi

for sample in "${SAMPLES[@]}"; do
    r1="${RAWDIR}/${sample}_1.fq.gz"
    r2="${RAWDIR}/${sample}_2.fq.gz"
    bam="${OUTDIR}/${sample}.bam"
    bai="${bam}.bai"
    vcf="${OUTDIR}/${sample}.vcf.gz"
    tbi="${vcf}.tbi"
    indelqual_bam="${OUTDIR}/${sample}.indelqual.bam"

    if [ ! -s "${r1}" ] || [ ! -s "${r2}" ]; then
        exit 1
    fi

    # --- alignment (idempotent) ---
    if [ ! -s "${bam}" ] || [ ! -s "${bai}" ]; then
        tmp_bam="${OUTDIR}/${sample}.tmp.bam"
        bwa mem -t "${THREADS}" "${REF}" "${r1}" "${r2}" \
            | samtools sort -@ "${THREADS}" -o "${tmp_bam}" -
        mv "${tmp_bam}" "${bam}"
        samtools index -@ "${THREADS}" "${bam}"
    fi

    # --- indel-quality-adjusted BAM for lofreq (idempotent intermediate) ---
    if [ ! -s "${indelqual_bam}" ] || [ ! -s "${indelqual_bam}.bai" ]; then
        tmp_iq="${OUTDIR}/${sample}.indelqual.tmp.bam"
        lofreq indelqual --dindel -f "${REF}" -o "${tmp_iq}" "${bam}"
        mv "${tmp_iq}" "${indelqual_bam}"
        samtools index -@ "${THREADS}" "${indelqual_bam}"
    fi

    # --- variant calling (idempotent) ---
    if [ ! -s "${vcf}" ] || [ ! -s "${tbi}" ]; then
        tmp_vcf="${OUTDIR}/${sample}.tmp.vcf"
        lofreq call-parallel --pp-threads "${THREADS}" --call-indels \
            -f "${REF}" -o "${tmp_vcf}" "${indelqual_bam}"
        bgzip -f "${tmp_vcf}"
        mv "${tmp_vcf}.gz" "${vcf}"
        tabix -f -p vcf "${vcf}"
    fi
done

# --- collapsed table (regenerated each run; cheap, keeps output current) ---
collapsed="${OUTDIR}/collapsed.tsv"
tmp_collapsed="${OUTDIR}/collapsed.tsv.tmp"

printf 'sample\tchrom\tpos\tref\talt\taf\n' > "${tmp_collapsed}"

for sample in "${SAMPLES[@]}"; do
    vcf="${OUTDIR}/${sample}.vcf.gz"
    bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "${vcf}" \
        | awk -v s="${sample}" 'BEGIN{OFS="\t"}{print s,$1,$2,$3,$4,$5}' >> "${tmp_collapsed}"
done

mv "${tmp_collapsed}" "${collapsed}"