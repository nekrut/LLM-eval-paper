#!/usr/bin/env bash
set -euo pipefail

THREADS=4
samples=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
ref_fasta="data/ref/chrM.fa"
results_dir="results"

mkdir -p "${results_dir}"

# Ensure reference is indexed once
if [[ ! -e "${ref_fasta}.fai" ]] || \
   [[ ! -e "$(dirname "${ref_fasta}")/.bwa_index_${ref_fasta##*/}" ]]; then
    samtools faidx "${ref_fasta}"
    bwa index "${ref_fasta}"
fi

for sample in "${samples[@]}"; do
    # Skip if output already exists and is up-to-date
    bam="${results_dir}/${sample}.bam"
    vcfgz="${results_dir}/${sample}.vcf.gz"
    tbi="${vcfgz%.gz}.tbi"

    if [[ -e "${vcfgz}" && -e "${tbi}" ]]; then
        # Check modification times of BAM and VCF to ensure idempotency
        bam_mod=$(stat -c %Y "${bam}")
        vcfgz_mod=$(stat -c %Y "${vcfgz}")
        if [[ ${bam_mod} -le ${vcfgz_mod} ]]; then
            continue
        fi
    fi

    # Align reads with bwa mem
    fq1="data/raw/${sample}_1.fq.gz"
    fq2="data/raw/${sample}_2.fq.gz"
    rg="@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA"
    bwa mem -R "${rg}" -t ${THREADS} "${ref_fasta}" "${fq1}" "${fq2}" | \
        samtools sort -@ ${THREADS} -o "${bam}"

    # Index BAM
    samtools index -@ ${THREADS} "${bam}"

    # Variant calling with lofreq
    lofreq call-parallel --pp-threads ${THREADS} --ref "${ref_fasta}" --out "${results_dir}/${sample}.vcf" \
        results/${sample}.bam

    # Compress and index VCF
    bgzip -c "${results_dir}/${sample}.vcf" > "${vcfgz}"
    tabix -p vcf "${vcfgz}"

    # Clean up uncompressed VCF
    rm "${results_dir}/${sample}.vcf"
done

# Collapse variants into a single TSV file
{
    echo "sample\tchrom\tpos\tref\talt\taf"
    for sample in "${samples[@]}"; do
        bcftools query -f '%SAMPLE%\t%CHROM%\t%POS%\t%REF%\t%ALT%\t%INFO/AF\n' \
            "${results_dir}/${sample}.vcf.gz" | sed "s/^/${sample}\t/"
    done
} > "${results_dir}/collapsed.tsv"