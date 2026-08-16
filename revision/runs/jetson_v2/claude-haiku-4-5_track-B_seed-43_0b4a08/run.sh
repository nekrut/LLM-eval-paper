#!/usr/bin/env bash
set -euo pipefail

# Configuration
THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
REF="data/ref/chrM.fa"
RAW_DIR="data/raw"
RESULTS_DIR="results"

# Create results directory
mkdir -p "$RESULTS_DIR"

# Index reference if not already done
if [ ! -f "$REF.bwt" ]; then
    bwa index "$REF"
fi

if [ ! -f "$REF.fai" ]; then
    samtools faidx "$REF"
fi

# Process each sample
for SAMPLE in "${SAMPLES[@]}"; do
    BAM_FILE="$RESULTS_DIR/${SAMPLE}.bam"
    BAI_FILE="$RESULTS_DIR/${SAMPLE}.bam.bai"
    VCF_FILE="$RESULTS_DIR/${SAMPLE}.vcf.gz"
    VCF_TBI_FILE="$RESULTS_DIR/${SAMPLE}.vcf.gz.tbi"
    
    # Align reads and generate BAM
    if [ ! -f "$BAM_FILE" ]; then
        bwa mem -t "$THREADS" "$REF" \
            "$RAW_DIR/${SAMPLE}_1.fq.gz" \
            "$RAW_DIR/${SAMPLE}_2.fq.gz" | \
        samtools view -bS | \
        samtools sort -o "$BAM_FILE" -
    fi
    
    # Index BAM
    if [ ! -f "$BAI_FILE" ]; then
        samtools index "$BAM_FILE"
    fi
    
    # Call variants using bcftools
    if [ ! -f "$VCF_FILE" ]; then
        bcftools mpileup -f "$REF" "$BAM_FILE" | \
        bcftools call -mv -Oz -o "$VCF_FILE" -
    fi
    
    # Index VCF
    if [ ! -f "$VCF_TBI_FILE" ]; then
        tabix -p vcf "$VCF_FILE"
    fi
done

# Create collapsed TSV
COLLAPSED="$RESULTS_DIR/collapsed.tsv"
if [ ! -f "$COLLAPSED" ]; then
    # Write header
    echo -e "sample\tchrom\tpos\tref\talt\taf" > "$COLLAPSED"
    
    # Process each VCF and extract variants
    for SAMPLE in "${SAMPLES[@]}"; do
        VCF_FILE="$RESULTS_DIR/${SAMPLE}.vcf.gz"
        
        # Extract variants and calculate AF from genotype
        zcat "$VCF_FILE" | awk -v sample="$SAMPLE" '
        BEGIN { FS="\t"; OFS="\t" }
        /^#/ { next }
        NF > 0 {
            chrom = $1
            pos = $2
            ref = $4
            alt = $5
            
            # Get genotype from 10th column (first sample)
            if (NF >= 10) {
                gt_field = $10
                split(gt_field, gt_parts, ":")
                gt = gt_parts[1]
            } else {
                gt = "."
            }
            
            # Calculate AF from genotype
            if (gt != ".") {
                gsub(/[|\/]/, " ", gt)
                
                ref_count = 0
                alt_count = 0
                n_fields = split(gt, alleles, " ")
                
                for (i = 1; i <= n_fields; i++) {
                    if (alleles[i] == "0") {
                        ref_count++
                    } else if (alleles[i] != ".") {
                        alt_count++
                    }
                }
                
                total = ref_count + alt_count
                if (total > 0) {
                    af = alt_count / total
                } else {
                    af = 0
                }
            } else {
                af = 0
            }
            
            printf "%s\t%s\t%s\t%s\t%s\t%.4f\n", sample, chrom, pos, ref, alt, af
        }
        ' >> "$COLLAPSED"
    done
fi