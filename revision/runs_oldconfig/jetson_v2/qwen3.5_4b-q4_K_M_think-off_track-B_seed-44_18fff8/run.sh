#!/usr/bin/env bash
set -euo pipefail

# Create results directory if it doesn't exist
mkdir -p results/

# Define sample list and reference file
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
REF_FILE="data/ref/chrM.fa"

# Function to check if output already exists (idempotency)
check_done() {
    local sample="$1"
    [[ -f "results/${sample}.bam.bai" ]] && return 0 || return 1
}

# Step 1: Index the reference genome once
if ! check_ref_indexed; then
    samtools faidx "$REF_FILE" > /dev/null
fi

check_ref_indexed() {
    [[ -f "${REF_FILE}.faix" ]] && return 0 || return 1
}

# Step 2: Process each sample (BWA-MEM alignment -> SAM/BAM)
for sample in "${SAMPLES[@]}"; do
    if check_done "$sample"; then
        continue # Skip if already done
    fi
    
    local_1="${sample}-bl" || true
    local_2="${sample}-ch" || true
    
    [[ -z "$local_1" ]] && { echo "Error: Missing files for sample $sample"; exit 1; }
    
    # Align using BWA-MEM (paired-end) to chrM.fa
    bwa mem -t 4 "$REF_FILE" \
        "${data/raw/${local_1}.fq.gz}" \
        "${data/raw/${local_2}.fq.gz}" | \
    samtools sort -@ 4 > "results/${sample}.sam" && \
    samtools view -bS "results/${sample}.sam" | \
    samtools index -o "results/${sample}.bam.bai"

done

# Step 3: Variant calling using LoFreq (sensitive mode) on each BAM
for sample in "${SAMPLES[@]}"; do
    if check_done "$sample"; then
        continue # Skip if already done
    fi
    
    lofreq call -f "$REF_FILE" \
        --min-qual 30 \
        --output-type vcf.gz \
        "results/${sample}.bam" > "results/${sample}.vcf.gz.tmp" && \
    bcftools index -t "results/${sample}.vcf.gz.tmp" && \
    mv "results/${sample}.vcf.gz.tmp" "results/${sample}.vcf.gz"

done

# Step 4: Collapse variants into a single TSV file with columns: sample, chrom, pos, ref, alt, af
{
    echo -e "sample\tchrom\tpos\tref\talt\taf"
    
    # Collect all VCFs and merge them (bcftools is fast enough for small mtDNA datasets)
    bcftools concat \
        --threads 4 \
        "${SAMPLES[@]}.vcf.gz" > "results/merged.vcf.tmp" && \
    
    # Filter to keep only mitochondrial variants (chrM or M, depending on VCF header naming; usually chrM in our case)
    bcftools view -i 'chrom="chrM"' "results/merged.vcf.tmp" | \
    bcftools filter --min-qual 30 > "results/filt.vcf.gz" && \
    
    # Index the filtered VCF for tabix (optional but good practice) and prepare SnpSift output
    bcftools index -o "results/filt.vcf.gz.tbi" "results/filt.vcf.gz.tmp" 2>/dev/null || true
    
    # Use SnpSift to extract specific fields: sample, chrom, pos, ref, alt, af (AD field)
    snpSift select \
        --format vcf \
        -i "results/filt.vcf.gz" | \
    awk 'BEGIN { FS="\t"; OFS="\t" } 
         /^#/ { print; next } 
         ENDFILE { if (!header_printed) header_printed=1; else print sample, chrom, pos, ref, alt, af }' > "results/collapsed.tsv.tmp"
    
    # Reconstruct the final collapsed file with proper header and data rows
    head -n 1 "results/filt.vcf.gz.tbi" | grep "^#" || true
    
    {
        echo -e "sample\tchrom\tpos\tref\talt\taf"
        
        snpSift select \
            --format vcf \
            -i "results/filt.vcf.gz.tmp" 2>/dev/null | \
        awk 'BEGIN { FS="\t"; OFS="\t" } 
             /^#/ || /#CHROM/ { next } 
             ENDFILE { if (!header_printed) header_printed=1; else print sample, chrom, pos, ref, alt, af }' > "results/collapsed.tsv.tmp"
        
        # Final cleanup and ensure correct format (SnpSift output is tabular by default when using --format vcf with specific fields if configured, but here we parse)
        cat results/filt.vcf.gz.tbi | grep -v "^#" || true
        
    } > "results/collapsed.tsv"

done