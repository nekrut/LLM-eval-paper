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
        bwa mem -t "$THREADS" \
            -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
            data/ref/chrM.fa \
            data/raw/${sample}_1.fq.gz \
            data/raw/${sample}_2.fq.gz |
        samtools sort -@ "$THREADS" -o results/"${sample}".bam
    fi

    # BAM indexing
    if [[ ! -f results/"${sample}".bam.bai ]]; then
        samtools index -@ "$THREADS" results/"${sample}".bam
    fi

    # Variant calling with lofreq
    vcf_out="results/${sample}.vcf"
    bam_file="results/${sample}.bam"
    if [[ ! -f "${vcf_out}.gz" ]]; then
        lofreq call-parallel --pp-threads "$THREADS" \
            --ref data/ref/chrM.fa \
            --out "${vcf_out}" \
            --sig \
            --bonf \
            "${bam_file}"
    fi

    # Compression and indexing
    if [[ ! -f results/"${sample}".vcf.gz ]]; then
        bgzip -c "${vcf_out}" > results/"${sample}.vcf.gz"
    fi
    if [[ ! -f results/"${sample}".vcf.gz.tbi ]]; then
        tabix -p vcf results/"${sample}.vcf.gz"
    fi

    # Cleanup intermediate uncompressed VCF
    rm -f "${vcf_out}"
done

# Collapse step
collapsed_tsv="results/collapsed.tsv"
if [[ ! -f "$collapsed_tsv" ]] || [[ results/*.vcf.gz -nt "$collapsed_tsv" ]]; then
    {
        echo -e "sample\tchrom\tpos\tref\talt\taf"
        for sample in "${samples[@]}"; do
            bcftools query -f '{sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' \
                results/"${sample}".vcf.gz
        done
    } > "$collapsed_tsv"
fi

exit 0