#!/usr/bin/env bash
set -euo pipefail
THREADS=4
mkdir -p results
samples=(M117-bl M117-ch M117C1-bl M117C1-ch)
ref="data/ref/chrM.fa"
index_prefix="${ref}.fai"
bwa_index_prefix="${ref}"
if [[ ! -e "${index_prefix}" ]]; then
    samtools faidx "${ref}"
fi
if [[ ! -e "${bwa_index_prefix}."* ]]; then
    bwa index "${ref}"
fi
for sample in "${samples[@]}"; do
    fastq1="data/raw/${sample}_1.fq.gz"
    fastq2="data/raw/${sample}_2.fq.gz"
    rg="@RG\\tID:${sample}\\tSM:${sample}\\tLB:${sample}\\tPL:ILLUMINA"
    if [[ -e "results/${sample}.bam.bai" ]]; then
        continue
    fi
    bwa mem -t "${THREADS}" -R "${rg}" "${ref}" "${fastq1}" "${fastq2}" | samtools sort -@ "${THREADS}" -o "results/${sample}.bam"
    if [[ -e "results/${sample}.bam.bai" ]]; then
        continue
    fi
    samtools index -@ "${THREADS}" "results/${sample}.bam"
    if [[ -e "results/${sample}.vcf.gz.tbi" ]]; then
        continue
    fi
    lofreq call-parallel --pp-threads "${THREADS}" --verbose --ref "${ref}" --out "results/${sample}.vcf" results/${sample}.bam
    bgzip -c "results/${sample}.vcf" > "results/${sample}.vcf.gz"
    rm -f "results/${sample}.vcf"
    tabix -p vcf "results/${sample}.vcf.gz"
    if [[ -e "results/collapsed.tsv" ]]; then
        collapsed_newer=false
        for sample in "${samples[@]}"; do
            tsv="results/collapsed.tsv"
            vcf_gz="results/${sample}.vcf.gz"
            if [[ "${vcf_gz}" -nt "${tsv}" ]]; then
                collapsed_newer=true
                break
            fi
        done
        if ! $collapsed_newer; then
            continue
        fi
    fi
    {
        printf "sample\tchrom\tpos\tref\talt\taf\n"
        for sample in "${samples[@]}"; do
            bcftools query -f '{sample}\\t%CHROM\\t%POS\\t%REF\\t%ALT\\t%INFO/AF\\n' results/${sample}.vcf.gz
        done
    } > "results/collapsed.tsv"