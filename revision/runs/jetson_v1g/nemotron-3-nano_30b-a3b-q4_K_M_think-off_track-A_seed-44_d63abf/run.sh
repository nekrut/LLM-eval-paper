#!/usr/bin/env bash
set -euo pipefail

THREADS=4
samples=(M117-bl M117-ch M117C1-bl M117C1-ch)

mkdir -p results

# Reference indexing (once)
if [[ ! -f data/ref/chrM.fa.fai ]]; then
    samtools faidx data/ref/chrM.fa
fi
if [[ ! -f data/ref/chrM.fa.amb ]]; then
    bwa index data/ref/chrM.fa
fi

# Per-sample processing loop
for sample in "${samples[@]}"; do
    # Alignment
    if [[ ! -f results/"${sample}".bam ]]; then
        bwa mem -t 4 -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
            data/ref/chrM.fa \
            data/raw/${sample}_1.fq.gz \
            data/raw/${sample}_2.fq.gz |
        samtools sort -@ 4 -o results/"${sample}".bam
    fi

    # BAM indexing
    if [[ ! -f results/"${sample}".bam.bai ]]; then
        samtools index -@ 4 results/"${sample}".bam
    fi

    # Variant calling with lofreq call-parallel
    if [[ ! -f results/"${sample}.vcf.gz" ]]; then
        lofreq call-parallel --pp-threads 4 \
            --ref data/ref/chrM.fa \
            --out results/"${sample}".vcf \
            results/"${sample}".bam
    fi

    # Compression and indexing
    if [[ ! -f results/"${sample}.vcf.gz" ]]; then
        bgzip -c results/"${sample}.vcf" > results/"${sample}.vcf.gz"
        tabix -p vcf results/"${sample}.vcf.gz"
        rm results/"${sample}.vcf"
    fi

    # Collapse step (rebuild if any VCF is newer)
    if [[ ! -f results/collapsed.tsv || results/collapsed.tsv < $(printf '%s\n' "${samples[@]/#/results/}" | sed 's/$/.vcf.gz/' | tr '\n' ' ') ]]; then
        {
            echo -e "sample\tchrom\tpos\tref\talt\taf"
            for s in "${samples[@]}"; do
                bcftools query -f '{sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' results/"${s}.vcf.gz"
            done
        } > results/collapsed.tsv.tmp && mv results/collapsed.tsv.tmp results/collapsed.tsv
    fi
done

exit 0