#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)

mkdir -p results

if [[ ! -f "data/ref/chrM.fa.fai" ]]; then
    samtools faidx data/ref/chrM.fa
fi

if [[ ! -f "data/ref/chrM.fa.amb" ]]; then
    bwa index data/ref/chrM.fa
fi

for sample in "${SAMPLES[@]}"; do
    if [[ ! -f "results/${sample}.bam" ]]; then
        bwa mem -t "${THREADS}" \
            -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
            data/ref/chrM.fa \
            data/raw/${sample}_1.fq.gz \
            data/raw/${sample}_2.fq.gz | \
            samtools sort -@ "${THREADS}" -o results/${sample}.bam
    fi
    
    if [[ ! -f "results/${sample}.bam.bai" ]]; then
        samtools index -@ "${THREADS}" results/${sample}.bam
    fi
    
    if [[ ! -f "results/${sample}.vcf.gz" ]]; then
        lofreq call-parallel --pp-threads "${THREADS}" --verbose \
            --ref data/ref/chrM.fa \
            --out results/${sample}.vcf \
            results/${sample}.bam
        bgzip results/${sample}.vcf
    fi
    
    if [[ ! -f "results/${sample}.vcf.gz.tbi" ]]; then
        tabix -p vcf results/${sample}.vcf.gz
    fi
done

rebuild_collapsed=false
if [[ ! -f "results/collapsed.tsv" ]]; then
    rebuild_collapsed=true
else
    for sample in "${SAMPLES[@]}"; do
        if [[ "results/${sample}.vcf.gz" -nt "results/collapsed.tsv" ]]; then
            rebuild_collapsed=true
            break
        fi
    done
fi

if [[ "${rebuild_collapsed}" == "true" ]]; then
    {
        printf "sample\tchrom\tpos\tref\talt\taf\n"
        for sample in "${SAMPLES[@]}"; do
            bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" \
                results/${sample}.vcf.gz
        done
    } > results/collapsed.tsv
fi