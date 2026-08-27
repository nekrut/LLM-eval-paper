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
    # Skip if all final outputs exist and are up-to-date
    if [[ -f "results/${sample}.bam.bai" && -f "results/${sample}.vcf.gz.tbi" && -f "results/collapsed.tsv" ]]; then
        continue
    fi

    # Alignment with bwa mem
    bwa mem -t "${THREADS}" \
        -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
        data/ref/chrM.fa \
        data/raw/${sample}_1.fq.gz \
        data/raw/${sample}_2.fq.gz |
        samtools sort -@ "${THREADS}" -o "results/${sample}.bam"

    # BAM indexing
    samtools index -@ "${THREADS}" "results/${sample}.bam"

    # Variant calling with lofreq call-parallel
    lofreq call-parallel --pp-threads 4 \
        --ref data/ref/chrM.fa \
        --out "results/${sample}.vcf" \
        results/"${sample}".bam

    # Compression and indexing
    bgzip -c "results/${sample}.vcf" > "results/${sample}.vcf.gz"
    tabix -p vcf "results/${sample}.vcf.gz"

    # Remove intermediate uncompressed VCF
    rm -f "results/${sample}.vcf"
done

# Collapse step: generate collapsed.tsv if any input VCF is newer
if [[ ! -f results/collapsed.tsv || data/ref/chrM.fa -nt results/collapsed.tsv ]]; then
    {
        printf 'sample\tchrom\tpos\tref\talt\taf\n'
        for sample in "${samples[@]}"; do
            bcftools query -f '{sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "results/${sample}.vcf.gz"
        done
    } > results/collapsed.tsv
fi

exit 0