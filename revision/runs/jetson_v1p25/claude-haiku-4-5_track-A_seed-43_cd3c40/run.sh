#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)

mkdir -p results

# Reference indexing
if [[ ! -f data/ref/chrM.fa.fai ]]; then
    samtools faidx data/ref/chrM.fa
fi

if [[ ! -f data/ref/chrM.fa.bwt ]]; then
    bwa index data/ref/chrM.fa
fi

# Per-sample processing
for sample in "${SAMPLES[@]}"; do
    bam_file="results/${sample}.bam"
    bai_file="results/${sample}.bam.bai"
    vcf_file="results/${sample}.vcf"
    vcf_gz_file="results/${sample}.vcf.gz"
    vcf_tbi_file="results/${sample}.vcf.gz.tbi"
    
    # Alignment and BAM indexing
    if [[ ! -f "${bai_file}" ]]; then
        bwa mem -t ${THREADS} -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
            data/ref/chrM.fa \
            data/raw/${sample}_1.fq.gz \
            data/raw/${sample}_2.fq.gz | \
            samtools sort -@ ${THREADS} -o "${bam_file}"
        samtools index -@ ${THREADS} "${bam_file}"
    fi
    
    # Variant calling, compression, and indexing
    if [[ ! -f "${vcf_tbi_file}" ]]; then
        if [[ ! -f "${vcf_gz_file}" ]]; then
            if [[ ! -f "${vcf_file}" ]]; then
                lofreq call-parallel --pp-threads ${THREADS} -f data/ref/chrM.fa \
                    -o "${vcf_file}" "${bam_file}"
            fi
            bgzip -f "${vcf_file}"
        fi
        tabix -p vcf "${vcf_gz_file}"
    fi
done

# Collapse step
collapsed_file="results/collapsed.tsv"
rebuild_collapsed=false

if [[ ! -f "${collapsed_file}" ]]; then
    rebuild_collapsed=true
else
    for sample in "${SAMPLES[@]}"; do
        if [[ "results/${sample}.vcf.gz" -nt "${collapsed_file}" ]]; then
            rebuild_collapsed=true
            break
        fi
    done
fi

if [[ "${rebuild_collapsed}" == true ]]; then
    {
        printf 'sample\tchrom\tpos\tref\talt\taf\n'
        for sample in "${SAMPLES[@]}"; do
            bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" \
                "results/${sample}.vcf.gz"
        done
    } > "${collapsed_file}"
fi