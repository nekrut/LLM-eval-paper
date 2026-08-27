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
    tbi_path="${results_dir}/${sample}.vcf.gz.tbi"
    bam_path="${results_dir}/${sample}.bam"

    if [[ -e "${vcf_path}" && -e "${tbi_path}" ]] && \
       [[ "${vcf_path}" -nt "data/raw/${sample}_1.fq.gz" ]] && \
       [[ "${vcf_path}" -nt "data/raw/${sample}_2.fq.gz" ]]; then
        continue
    fi

    # Alignment with bwa mem
    bwa mem -t "${THREADS}" -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
        "${ref_fasta}" "data/raw/${sample}_1.fq.gz" "data/raw/${sample}_2.fq.gz" |
    samtools sort -@ "${THREADS}" -o "${bam_path}"

    # BAM indexing
    samtools index -@ "${THREADS}" "${bam_path}"

    # Variant calling with lofreq
    lofreq call-parallel --pp-threads "${THREADS}" \
        --ref "${ref_fasta}" --out "${results_dir}/${sample}.vcf" \
        "${bam_path}"
    
    # Compress and index VCF
    bgzip -c "${results_dir}/${sample}.vcf" > "${vcf_path}"
    tabix -p vcf "${vcf_path}"
    rm "${results_dir}/${sample}.vcf"
done

# Collapse variants into a single TSV file
{
    echo "sample\tchrom\tpos\tref\talt\taf"
    for sample in "${samples[@]}"; do
        bcftools query -f '%SAMPLE%\t%CHROM%\t%POS%\t%REF%\t%ALT%\t%INFO/AF\n' \
            "${results_dir}/${sample}.vcf.gz" | sed "1s/^/${sample}\t/"
    done
} > "${results_dir}/collapsed.tsv"