#!/usr/bin/env bash
set -euo pipefail

THREADS=4

# Create output directory if needed
mkdir -p results

# Index reference if not already indexed
if [[ ! -f data/ref/chrM.fa.bwt ]]; then
    bwa index data/ref/chrM.fa
fi

# Process each sample
for sample in M117-bl M117-ch M117C1-bl M117C1-ch; do
    bam_file="results/${sample}.bam"
    vcf_file="results/${sample}.vcf.gz"
    
    # Skip if already processed (idempotent)
    if [[ -f "${bam_file}" && -f "${bam_file}.bai" && -f "${vcf_file}" && -f "${vcf_file}.tbi" ]]; then
        continue
    fi
    
    # Map reads with bwa mem
    bwa mem -t ${THREADS} data/ref/chrM.fa \
        "data/raw/${sample}_1.fq.gz" \
        "data/raw/${sample}_2.fq.gz" | \
    samtools view -b - | \
    samtools sort -@ ${THREADS} -o "${bam_file}" -
    
    # Index BAM
    samtools index "${bam_file}"
    
    # Call variants with lofreq and compress with bcftools
    lofreq mpileup -f data/ref/chrM.fa "${bam_file}" | \
    lofreq call -f data/ref/chrM.fa -o - - | \
    bcftools view -Oz -o "${vcf_file}" -
    
    # Index VCF with tabix
    tabix -p vcf "${vcf_file}"
done

# Create collapsed TSV from all VCFs
{
    printf "sample\tchrom\tpos\tref\talt\taf\n"
    for sample in M117-bl M117-ch M117C1-bl M117C1-ch; do
        vcf_file="results/${sample}.vcf.gz"
        if [[ -f "${vcf_file}" ]]; then
            bcftools query -f '%CHROM\t%POS\t%REF\t%ALT[\t%AF]\n' "${vcf_file}" | \
            awk -F'\t' -v sample="${sample}" 'NF>=5 {print sample"\t"$1"\t"$2"\t"$3"\t"$4"\t"$5}'
        fi
    done
} > results/collapsed.tsv