#!/usr/bin/env bash
set -euo pipefail

THREADS=4
REF="data/ref/chrM.fa"
RESULTS="results"

# Create results directory
mkdir -p "$RESULTS"

# Index reference if not already indexed
if [[ ! -f "${REF}.bwt" ]]; then
    bwa index "$REF"
fi

# Ensure samtools fai index for reference
if [[ ! -f "${REF}.fai" ]]; then
    samtools faidx "$REF"
fi

# Define samples
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

# Map and call variants for each sample
for SAMPLE in "${SAMPLES[@]}"; do
    R1="data/raw/${SAMPLE}_1.fq.gz"
    R2="data/raw/${SAMPLE}_2.fq.gz"
    BAM="${RESULTS}/${SAMPLE}.bam"
    BAM_IDX="${RESULTS}/${SAMPLE}.bam.bai"
    VCF="${RESULTS}/${SAMPLE}.vcf.gz"
    VCF_IDX="${RESULTS}/${SAMPLE}.vcf.gz.tbi"
    VCF_TEMP="${RESULTS}/${SAMPLE}.vcf"
    
    # Map reads
    if [[ ! -f "$BAM" ]]; then
        bwa mem -t "$THREADS" "$REF" "$R1" "$R2" | \
            samtools sort -@ "$THREADS" -o "$BAM" -
    fi
    
    # Index BAM
    if [[ ! -f "$BAM_IDX" ]]; then
        samtools index -@ "$THREADS" "$BAM"
    fi
    
    # Call variants using lofreq
    if [[ ! -f "$VCF" ]]; then
        lofreq call -f "$REF" -o "$VCF_TEMP" "$BAM"
        bgzip -f "$VCF_TEMP"
    fi
    
    # Index VCF
    if [[ ! -f "$VCF_IDX" ]]; then
        tabix -p vcf "$VCF"
    fi
done

# Collapse VCFs into single TSV
OUTPUT_TSV="${RESULTS}/collapsed.tsv"
if [[ ! -f "$OUTPUT_TSV" ]]; then
    {
        # Write header
        echo -e "sample\tchrom\tpos\tref\talt\taf"
        
        # Process each VCF
        for SAMPLE in "${SAMPLES[@]}"; do
            VCF="${RESULTS}/${SAMPLE}.vcf.gz"
            
            # Extract variants with allele frequency
            bcftools query -f "%CHROM\t%POS\t%REF\t%ALT\t%AF\n" "$VCF" | \
            while IFS=$'\t' read -r chrom pos ref alt af; do
                echo -e "${SAMPLE}\t${chrom}\t${pos}\t${ref}\t${alt}\t${af}"
            done
        done
    } > "$OUTPUT_TSV"
fi

exit 0