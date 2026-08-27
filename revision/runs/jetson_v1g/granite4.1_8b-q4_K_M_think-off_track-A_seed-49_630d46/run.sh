#!/usr/bin/env bash
set -euo pipefail

THREADS=4
samples=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
ref_fasta="data/ref/chrM.fa"
results_dir="results"

mkdir -p "${results_dir}"

# Ensure reference index exists
if [[ ! -f "${ref_fasta}.fai" ]] || \
   [[ ! -f "$(dirname "${ref_fasta}")"/chrM.fa.amb ]] || \
   [[ ! -f "$(dirname "${ref_fasta}")"/chrM.fa.ann ]] || \
   [[ ! -f "$(dirname "${ref_fasta}")"/chrM.fa.bwt ]] || \
   [[ ! -f "$(dirname "${ref_fasta}")"/chrM.fa.pac ]] || \
   [[ ! -f "$(dirname "${ref_fasta}")"/chrM.fa.sa" ]]; then
    samtools faidx "${ref_fasta}"
    bwa index "${ref_fasta}"
fi

for sample in "${samples[@]}"; do
    # Skip if output already exists and is up-to-date
    bam="${results_dir}/${sample}.bam"
    vcfgz="${results_dir}/${sample}.vcf.gz"
    tbi="${results_dir}/${sample}.vcf.gz.tbi"

    if [[ -e "${vcfgz}" ]] && \
       [[ "${vcfgz}" -nt "data/raw/${sample}_1.fq.gz" ]] && \
       [[ "${vcfgz}" -nt "data/raw/${sample}_2.fq.gz" ]]; then
        continue
    fi

    # Alignment with bwa mem
    rg="@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA"
    bwa mem -R "${rg}" -t ${THREADS} \
        "data/raw/${sample}_1.fq.gz" \
        "data/raw/${sample}_2.fq.gz" \
        "${ref_fasta}" | \
    samtools sort -@ ${THREADS} -o "${bam}"

    # Index BAM
    samtools index -@ ${THREADS} "${bam}"

    # Variant calling with lofreq
    lofreq call-parallel --pp-threads 4 --verbose \
        --ref "${ref_fasta}" --out "${results_dir}/${sample}.vcf" \
        "${bam}"
    
    # Compress and index VCF
    bgzip -c "${results_dir}/${sample}.vcf" > "${vcfgz}"
    tabix -p vcf "${vcfgz}"
    rm "${results_dir}/${sample}.vcf"
done

# Collapse variants into a single TSV file
{
    echo "sample\tchrom\tpos\tref\talt\taf"
    for sample in "${samples[@]}"; do
        bcftools query -f '%SAMPLE%\t%CHROM%\t%POS%\t%REF%\t%ALT%\t%INFO/AF\n' \
            "${results_dir}/${sample}.vcf.gz" | \
        sed "s/^/${sample}\t/"
    done
} > "${results_dir}/collapsed.tsv"