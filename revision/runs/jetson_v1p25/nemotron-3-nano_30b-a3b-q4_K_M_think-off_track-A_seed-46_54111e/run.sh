#!/usr/bin/env bash
set -euo pipefail

THREADS=4
mkdir -p results

samples=(M117-bl M117-ch M117C1-bl M117C1-ch)

for sample in "${samples[@]}"; do
    bam="results/${sample}.bam"
    bai="results/${sample}.bam.bai"
    vcf_uncomp="results/${sample}.vcf"
    vcf_gz="results/${sample}.vcf.gz"
    tbi="results/${sample}.vcf.gz.tbi"

    if [[ -s "${tbi}" ]]; then
        continue
    fi

    if [[ ! -s "${bam}" ]]; then
        fastq1="data/raw/${sample}_1.fq.gz"
        fastq2="data/raw/${sample}_2.fq.gz"
        rg="@RG\\tID:${sample}\\tSM:${sample}\\tLB:${sample}\\tPL:ILLUMINA"

        bwa mem -t "${THREADS}" -R "${rg}" data/ref/chrM.fa "${fastq1}" "${fastq2}" |
            samtools sort -@ 4 -o "${bam}"
    fi

    if [[ ! -s "${bai}" ]]; then
        samtools index -@ 4 "${bam}"
    fi

    if [[ ! -s "${vcf_gz}.tbi" ]]; then
        lofreq call-parallel --pp-threads 4 -f data/ref/chrM.fa -o "${vcf_uncomp}" "${bam}"
        bgzip -c "${vcf_uncomp}" > "${vcf_gz}"
        tabix -p vcf "${vcf_gz}"
        rm -f "${vcf_uncomp}"
    fi
done

collapsed="results/collapsed.tsv"
if [[ ! -s "${collapsed}" ]] || newer "${vcf_gz}" "${collapsed}" >/dev/null 2>&1; then
    {
        printf "sample\tchrom\tpos\tref\talt\taf\n"
        for sample in "${samples[@]}"; do
            vcf="results/${sample}.vcf.gz"
            bcftools query -f '{sample}\\t%CHROM\\t%POS\\t%REF\\t%ALT\\t%INFO/AF\\n' "${vcf}"
        done
    } > "${collapsed}"
fi

exit 0