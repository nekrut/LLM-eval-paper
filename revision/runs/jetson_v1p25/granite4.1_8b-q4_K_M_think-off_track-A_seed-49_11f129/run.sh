#!/usr/bin/env bash
set -euo pipefail

THREADS=4
samples=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
ref_fasta="data/ref/chrM.fa"
results_dir="results"

mkdir -p "${results_dir}"

# Ensure reference index exists
if [[ ! -f "${ref_fasta}.fai" ]] || \
   [[ ! -f "$(dirname "${ref_fasta}")/$(basename "${ref_fasta}" .fa).amb" ]]; then
    samtools faidx "${ref_fasta}"
    bwa index "${ref_fasta}"
fi

for sample in "${samples[@]}"; do
    # Skip if VCF and its index already exist and are up-to-date
    vcf_path="${results_dir}/${sample}.vcf.gz"
    tbi_path="${vcf_path%.gz}.tbi"
    bam_path="${results_dir}/${sample}.bam"

    if [[ -e "${vcf_path}" && -e "${tbi_path}" ]] && \
       (( $(stat -c %Y "${vcf_path}") > $(stat -c %Y "${bam_path}")) ); then
        continue
    fi

    # Align reads with bwa mem
    fq1="data/raw/${sample}_1.fq.gz"
    fq2="data/raw/${sample}_2.fq.gz"
    rg="@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA"

    bwa mem -t "${THREADS}" -R "${rg}" "${ref_fasta}" "${fq1}" "${fq2}" |
        samtools sort -@ "${THREADS}" -o "${bam_path}"

    # Index BAM
    samtools index -@ "${THREADS}" "${bam_path}"

    # Variant calling with lofreq
    lofreq call-parallel --pp-threads "${THREADS}" -f "${ref_fasta}" -o "${results_dir}/${sample}.vcf" "${bam_path}"

    # Compress and index VCF
    bgzip -f "${results_dir}/${sample}.vcf"
    tabix -p vcf "${results_dir}/${sample}.vcf.gz"

    # Clean up uncompressed VCF
    rm "${results_dir}/${sample}.vcf"
done

# Collapse variants into a single TSV file
{
    echo "sample\tchrom\tpos\tref\talt\taf"
    for sample in "${samples[@]}"; do
        bcftools query -f '%SAMPLE%\t%CHROM%\t%POS%\t%REF%\t%ALT%\t%INFO/AF\n' "${results_dir}/${sample}.vcf.gz" \
            | sed "s/^/${sample}\t/"
    done
} > "${results_dir}/collapsed.tsv"