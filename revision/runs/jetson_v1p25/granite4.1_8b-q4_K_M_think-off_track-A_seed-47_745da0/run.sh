#!/usr/bin/env bash
set -euo pipefail

THREADS=4
samples=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
ref_fasta="data/ref/chrM.fa"
results_dir="results"

mkdir -p "${results_dir}"

# Ensure reference index exists
if [[ ! -f "${ref_fasta}.fai" ]] || \
   [[ ! -f "$(dirname "${ref_fasta}")"/chrM.fa.bwt ]]; then
    samtools faidx "${ref_fasta}"
    bwa index "${ref_fasta}"
fi

for sample in "${samples[@]}"; do
    # Skip if output already exists and is up-to-date
    bam="${results_dir}/${sample}.bam"
    vcfgz="${results_dir}/${sample}.vcf.gz"
    tbi="${results_dir}/${sample}.vcf.gz.tbi"

    if [[ -e "${vcfgz}" && -e "${tbi}" ]] && \
       [[ "${vcfgz}" -nt "data/raw/${sample}_1.fq.gz" ]] && \
       [[ "${vcfgz}" -nt "data/raw/${sample}_2.fq.gz" ]]; then
        continue
    fi

    # Align reads with bwa mem
    fq1="data/raw/${sample}_1.fq.gz"
    fq2="data/raw/${sample}_2.fq.gz"
    rg="@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA"

    bwa mem -t "${THREADS}" -R "${rg}" "${ref_fasta}" \
        "${fq1}" "${fq2}" | \
        samtools sort -@ "${THREADS}" -o "${bam}"

    # Index BAM
    samtools index -@ "${THREADS}" "${bam}"

    # Variant calling with lofreq
    vcf="${results_dir}/${sample}.vcf"
    lofreq call-parallel --pp-threads "${THREADS}" \
        -f "${ref_fasta}" -o "${vcf}" "${bam}"

    # Compress and index VCF
    bgzip -c "${vcf}" > "${vcfgz}"
    tabix -p vcf "${vcfgz}"
    rm "${vcf}"

done

# Collapse variants into a single TSV file
header="sample\tchrom\tpos\tref\talt\taf"
for sample in "${samples[@]}"; do
    bcftools query -f '%SAMPLE%\t%CHROM%\t%POS%\t%REF%\t%ALT%\t%INFO/AF\n' \
        "results/${sample}.vcf.gz" >> "${results_dir}/collapsed.tsv"
done

echo -e "${header}" > "${results_dir}/collapsed.tsv"

exit 0