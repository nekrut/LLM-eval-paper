#!/usr/bin/env bash
set -euo pipefail

THREADS=4
samples=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
ref_fasta="data/ref/chrM.fa"
results_dir="results"

mkdir -p "${results_dir}"

# Reference indexing (once)
if [[ ! -e "${ref_fasta}.fai" ]] || \
   [[ ! -e "$(dirname "${ref_fasta}")/chrM.fa.amb" ]] || \
   [[ ! -e "$(dirname "${ref_fasta}")/chrM.fa.ann" ]] || \
   [[ ! -e "$(dirname "${ref_fasta}")/chrM.fa.bwt" ]] || \
   [[ ! -e "$(dirname "${ref_fasta}")/chrM.fa.pac" ]] || \
   [[ ! -e "$(dirname "${ref_fasta}")/chrM.fa.sa" ]]; then
    samtools faidx "${ref_fasta}"
    bwa index "${ref_fasta}"
fi

for sample in "${samples[@]}"; do
    # Check if all per-sample outputs are up-to-date
    bam="${results_dir}/${sample}.bam"
    vcf_gz="${results_dir}/${sample}.vcf.gz"
    tbi="${results_dir}/${sample}.vcf.gz.tbi"

    if [[ -e "${bam}" && -e "${vcf_gz}" && -e "${tbi}" ]]; then
        # All artifacts exist; skip processing for this sample
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
    lofreq call-parallel --pp-threads ${THREADS} --ref "${ref_fasta}" --out "$(dirname "${bam}")/${sample}.vcf" \
        results/"${sample}".bam

    # Compress and index VCF
    bgzip -c "$(dirname "${bam}")/${sample}.vcf" > "${vcf_gz}"
    tabix -p vcf "${vcf_gz}" && rm "$(dirname "${bam}")/${sample}.vcf"

    # Create .tbi (already created by tabix)
done

# Collapse step to results/collapsed.tsv
{
    echo "sample\tchrom\tpos\tref\talt\taf"
    for sample in "${samples[@]}"; do
        bcftools query -f '%SAMPLE%\t%CHROM%\t%POS%\t%REF%\t%ALT%\t%INFO/AF\n' \
            "${results_dir}/${sample}.vcf.gz" | sed "1s/^/${sample}\t/"
    done
} > "${results_dir}/collapsed.tsv"