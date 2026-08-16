#!/usr/bin/env bash
set -euo pipefail

# Globals
THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

# Create results directory
mkdir -p results

# Step 2: Reference indexing
if [[ ! -f data/ref/chrM.fa.fai ]]; then
    samtools faidx data/ref/chrM.fa
fi

if [[ ! -f data/ref/chrM.fa.amb ]]; then
    bwa index data/ref/chrM.fa
fi

# Per-sample processing
for sample in "${SAMPLES[@]}"; do
    # Step 3-4: Alignment and convert to sorted BAM
    if [[ ! -f results/"${sample}".bam ]]; then
        bwa mem -t "${THREADS}" -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
            data/ref/chrM.fa \
            data/raw/"${sample}"_1.fq.gz \
            data/raw/"${sample}"_2.fq.gz | \
            samtools sort -@ "${THREADS}" -o results/"${sample}".bam
    fi
    
    # Step 5: BAM indexing
    if [[ ! -f results/"${sample}".bam.bai ]]; then
        samtools index -@ "${THREADS}" results/"${sample}".bam
    fi
    
    # Step 6-7: Variant calling with lofreq and compress
    if [[ ! -f results/"${sample}".vcf.gz ]]; then
        lofreq call-parallel --pp-threads "${THREADS}" --verbose \
            --ref data/ref/chrM.fa --out results/"${sample}".vcf \
            results/"${sample}".bam
        bgzip -f results/"${sample}".vcf
        tabix -p vcf results/"${sample}".vcf.gz
    fi
    
    # Ensure .vcf.gz.tbi exists (idempotent)
    if [[ ! -f results/"${sample}".vcf.gz.tbi ]]; then
        tabix -p vcf results/"${sample}".vcf.gz
    fi
done

# Step 8: Collapse to TSV
rebuild_tsv=false
if [[ ! -f results/collapsed.tsv ]]; then
    rebuild_tsv=true
else
    for sample in "${SAMPLES[@]}"; do
        if [[ results/collapsed.tsv -ot results/"${sample}".vcf.gz ]]; then
            rebuild_tsv=true
            break
        fi
    done
fi

if [[ ${rebuild_tsv} == true ]]; then
    {
        printf $'sample\tchrom\tpos\tref\talt\taf\n'
        for sample in "${SAMPLES[@]}"; do
            bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" \
                results/"${sample}".vcf.gz
        done
    } > results/collapsed.tsv
fi