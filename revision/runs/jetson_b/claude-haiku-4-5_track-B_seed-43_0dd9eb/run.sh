#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

mkdir -p results

# Index reference genome
if [[ ! -f data/ref/chrM.fa.amb ]]; then
    bwa index data/ref/chrM.fa
fi

if [[ ! -f data/ref/chrM.fa.fai ]]; then
    samtools faidx data/ref/chrM.fa
fi

# Process each sample
for sample in "${SAMPLES[@]}"; do
    # Skip if already complete
    if [[ -f "results/${sample}.bam" && -f "results/${sample}.bam.bai" && \
          -f "results/${sample}.vcf.gz" && -f "results/${sample}.vcf.gz.tbi" ]]; then
        continue
    fi
    
    # Align paired-end reads
    bwa mem -t $THREADS data/ref/chrM.fa data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz | \
        samtools view -b -o results/${sample}.tmp.bam -
    
    # Sort BAM
    samtools sort -@ $THREADS -o results/${sample}.bam results/${sample}.tmp.bam
    rm -f results/${sample}.tmp.bam
    
    # Index BAM
    samtools index -@ $THREADS results/${sample}.bam
    
    # Call variants
    lofreq call -f data/ref/chrM.fa -o results/${sample}.vcf results/${sample}.bam
    
    # Compress VCF
    bcftools view -Oz -o results/${sample}.vcf.gz results/${sample}.vcf
    rm -f results/${sample}.vcf
    
    # Index VCF
    tabix -p vcf results/${sample}.vcf.gz
done

# Generate collapsed variant table
if [[ ! -f "results/collapsed.tsv" ]]; then
    {
        echo -e "sample\tchrom\tpos\tref\talt\taf"
        
        for sample in "${SAMPLES[@]}"; do
            if [[ -f "results/${sample}.vcf.gz" ]]; then
                bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "results/${sample}.vcf.gz"
            fi
        done
    } > results/collapsed.tsv
fi