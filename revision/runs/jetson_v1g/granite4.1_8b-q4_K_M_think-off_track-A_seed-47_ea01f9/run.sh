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
    if [[ -e "${vcf_gz}" && -e "${tbi}" ]] && \
       [[ "${vcf_gz}" -nt "${bam}" ]]; then
        continue
    fi

    # Alignment with bwa mem
    fq1="data/raw/${sample}_1.fq.gz"
    fq2="data/raw/${sample}_2.fq.gz"
    rg="@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA"
    bwa mem -R "${rg}" -t ${THREADS} "${ref_fasta}" \
        "${fq1}" "${fq2}" | \
        samtools sort -@ ${THREADS} -o "${bam}"

    # BAM indexing
    samtools index -@ ${THREADS} "${bam}"

    # Variant calling with lofreq
    lofreq call-parallel --pp-threads 4 --verbose \
        --ref "${ref_fasta}" --out "${results_dir}/${sample}.vcf" \
        results/${sample}.bam

    # Compress and index VCF, remove uncompressed VCF
    bgzip -c "${results_dir}/${sample}.vcf" > "${vcf_gz}"
    tabix -p vcf "${vcf_gz}"
    rm "${results_dir}/${sample}.vcf"

    # Update timestamp of BAM to ensure collapse step runs if needed
    touch "${bam}"
done

# Collapse variants into a single TSV file
{
    echo "sample\tchrom\tpos\tref\talt\taf"
    for sample in "${samples[@]}"; do
        bcftools query -f '%SAMPLE%\t%CHROM%\t%POS%\t%REF%\t%ALT%\t%INFO/AF\n' \
            "${results_dir}/${sample}.vcf.gz" \
            | sed "s/^/${sample}\t/"
    done
} > "${results_dir}/collapsed.tsv"

exit 0