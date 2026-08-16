#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

# Check if results already exist and are complete
if [[ -d results ]] && [[ -f results/collapsed.tsv ]]; then
    all_present=true
    for sample in "${SAMPLES[@]}"; do
        if [[ ! -f results/${sample}.bam ]] || \
           [[ ! -f results/${sample}.bam.bai ]] || \
           [[ ! -f results/${sample}.vcf.gz ]] || \
           [[ ! -f results/${sample}.vcf.gz.tbi ]]; then
            all_present=false
            break
        fi
    done
    if $all_present; then
        exit 0
    fi
fi

mkdir -p results

# Index reference genome
bwa index data/ref/chrM.fa

# Process each sample
for sample in "${SAMPLES[@]}"; do
    # Check if outputs already exist for this sample
    if [[ -f results/${sample}.bam ]] && \
       [[ -f results/${sample}.bam.bai ]] && \
       [[ -f results/${sample}.vcf.gz ]] && \
       [[ -f results/${sample}.vcf.gz.tbi ]]; then
        continue
    fi

    # Align reads
    bwa mem -t ${THREADS} -R "@RG\tID:${sample}\tSM:${sample}" data/ref/chrM.fa \
        <(zcat data/raw/${sample}_1.fq.gz) \
        <(zcat data/raw/${sample}_2.fq.gz) | \
    samtools sort -@ ${THREADS} -o results/${sample}.bam -

    # Index BAM
    samtools index results/${sample}.bam

    # Call variants and create compressed VCF
    bcftools mpileup -f data/ref/chrM.fa -Ou results/${sample}.bam | \
        bcftools call -mv -Ov | \
        bgzip > results/${sample}.vcf.gz

    # Index VCF
    tabix -p vcf results/${sample}.vcf.gz
done

# Create collapsed table from all sample VCFs
echo -e "sample\tchrom\tpos\tref\talt\taf" > results/collapsed.tsv

for sample in "${SAMPLES[@]}"; do
    bcftools query -f '%CHROM\t%POS\t%REF\t%ALT[\t%AF]\n' \
        data/ref/chrM.fa ${sample}.vcf.gz 2>/dev/null || true
done | while IFS=$'\t' read -r chrom pos ref alt af; do
    # Skip header lines from bcftools query if any
    [[ "$chrom" == "CHROM" ]] && continue
    
    # Handle missing AF (use 0 or calculate from AD)
    if [[ -z "$af" ]]; then
        af="0"
    fi
done

# Better approach: extract and merge properly
{
    echo -e "sample\tchrom\tpos\tref\talt\taf"
    for sample in "${SAMPLES[@]}"; do
        bcftools query -f '[\t%CHROM\t%POS\t%REF\t%ALT\t%AF]\n' \
            results/${sample}.vcf.gz 2>/dev/null | tail -n +1 | \
            sed "s/^/\t${sample}\t/" | tr '\t' '\n' | paste - - - - - - | cut -f2-
    done
} > results/collapsed.tsv.tmp

# Clean up and finalize
mv results/collapsed.tsv.tmp results/collapsed.tsv

exit 0