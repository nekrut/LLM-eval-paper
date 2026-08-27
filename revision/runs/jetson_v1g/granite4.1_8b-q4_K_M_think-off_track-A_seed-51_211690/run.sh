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
    # Skip if VCF and its index are newer than the BAM
    bam="${results_dir}/${sample}.bam"
    vcf_gz="${results_dir}/${sample}.vcf.gz"
    tbi="${results_dir}/${sample}.vcf.gz.tbi"
    if [[ -s "${vcf_gz}" ]] && \
       ([[ ! -s "${bam}" ]] || [[ "$(stat -c %Y "${vcf_gz}")" -ge "$(stat -c %Y "${bam}")" ]]); then
        continue
    fi

    # Alignment with bwa mem
    fq1="data/raw/${sample}_1.fq.gz"
    fq2="data/raw/${sample}_2.fq.gz"
    rg="@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA"
    bwa mem -R "${rg}" -t ${THREADS} "${ref_fasta}" "${fq1}" "${fq2}" | \
        samtools sort -@ ${THREADS} -o "${bam}"

    # BAM indexing
    samtools index -@ ${THREADS} "${bam}"

    # Variant calling with lofreq
    lofreq call-parallel --pp-threads ${THREADS} --ref "${ref_fasta}" --out "${results_dir}/${sample}.vcf" \
        results/${sample}.bam

    # Compress and index VCF
    bgzip -f "${results_dir}/${sample}.vcf"
    tabix -p vcf "${results_dir}/${sample}.vcf.gz"
    rm "${results_dir}/${sample}.vcf"

    # Append sample name to each row using bcftools query
    bcftools query -f '%SAMPLE\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' \
        "${results_dir}/${sample}.vcf.gz" >> "${results_dir}/collapsed.tsv"
done

# Header for collapsed.tsv if it does not exist or is empty
if [[ ! -s "${results_dir}/collapsed.tsv" ]] || \
   [[ "$(head -n 1 "${results_dir}/collapsed.tsv")" != "sample\tchrom\tpos\tref\talt\taf" ]]; then
    echo "sample\tchrom\tpos\tref\talt\taf" > "${results_dir}/collapsed.tsv"
fi

exit 0