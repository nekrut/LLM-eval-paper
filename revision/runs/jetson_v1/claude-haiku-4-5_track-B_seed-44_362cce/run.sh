#!/usr/bin/env bash
set -euo pipefail

THREADS=4
mkdir -p results

SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

# Index reference genome
if [ ! -f data/ref/chrM.fa.bwt ]; then
    bwa index data/ref/chrM.fa
fi

if [ ! -f data/ref/chrM.fa.fai ]; then
    samtools faidx data/ref/chrM.fa
fi

# Process each sample
for sample in "${SAMPLES[@]}"; do
    # Alignment and sorting
    if [ ! -f "results/${sample}.bam" ]; then
        bwa mem -t $THREADS data/ref/chrM.fa data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz | \
            samtools view -@ $THREADS -b | \
            samtools sort -@ $THREADS -o results/${sample}.bam -
    fi
    
    # Index BAM file
    if [ ! -f "results/${sample}.bam.bai" ]; then
        samtools index results/${sample}.bam
    fi
    
    # Variant calling
    if [ ! -f "results/${sample}.vcf.gz" ]; then
        bcftools mpileup -f data/ref/chrM.fa results/${sample}.bam | \
            bcftools call -mv -o results/${sample}.vcf
        
        # Add AF field to VCF
        bcftools +fill-tags results/${sample}.vcf -o results/${sample}.vcf.tmp -- -t AF
        mv results/${sample}.vcf.tmp results/${sample}.vcf
        
        # Compress VCF
        bgzip -f results/${sample}.vcf
    fi
    
    # Index VCF file
    if [ ! -f "results/${sample}.vcf.gz.tbi" ]; then
        tabix -p vcf results/${sample}.vcf.gz
    fi
done

# Create collapsed TSV with all variants
if [ ! -f results/collapsed.tsv ]; then
    {
        echo -e "sample\tchrom\tpos\tref\talt\taf"
        for sample in "${SAMPLES[@]}"; do
            if [ -f "results/${sample}.vcf.gz" ]; then
                bcftools query -f "$sample\t%CHROM\t%POS\t%REF\t%ALT\t%AF\n" "results/${sample}.vcf.gz"
            fi
        done
    } > results/collapsed.tsv
fi