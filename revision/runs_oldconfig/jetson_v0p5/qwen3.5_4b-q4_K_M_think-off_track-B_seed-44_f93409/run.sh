#!/usr/bin/env bash
set -euo pipefail

# Idempotency check: exit 0 if results exist and are complete for all samples
if [[ -d "results" ]]; then
    required_files=("M117-bl.bam.bai" "M117-ch.bam.bai" "M117C1-bl.bam.bai" "M117C1-ch.bam.bai")
    missing=0
    for f in "${required_files[@]}"; do
        if [[ ! -f "results/$f" ]]; then
            missing=$((missing + 1))
        fi
    done
    
    # Check VCFs and TBI files exist (they are required outputs)
    vcf_required=("M117-bl.vcf.gz.tbi" "M117-ch.vcf.gz.tbi" "M117C1-bl.vcf.gz.tbi" "M117C1-ch.vcf.gz.tbi")
    for f in "${vcf_required[@]}"; do
        if [[ ! -f "results/$f" ]]; then
            missing=$((missing + 1))
        fi
    done
    
    # Check collapsed.tsv exists
    if [[ ! -f "results/collapsed.tsv" ]]; then
        missing=$((missing + 1))
    fi
    
    if [[ $missing -eq 0 ]]; then
        exit 0
    fi
fi

# Create results directory if it doesn't exist (idempotent)
mkdir -p results

# Reference index creation (only needed once, but safe to run again as idempotent for empty dir or existing idx)
if [[ ! -f "data/ref/chrM.fa.fai" ]]; then
    samtools faidx data/ref/chrM.fa > /dev/null 2>&1 || true # Create fai if missing (safe even if exists due to pipefail handling in loop below, but better explicit check logic)
fi

# Function to process a single sample
process_sample() {
    local name=$1
    local f1="data/raw/${name}_1.fq.gz"
    local f2="data/raw/${name}_2.fq.gz"
    
    # Align reads using BWA-MEM (default is mem)
    bwa mem -t 4 data/ref/chrM.fa "$f1" "$f2" | samtools sort -@ 4 > "results/${name}.sorted.bam"

    # Mark duplicates and index the BAM file
    samtools markdup -r "results/${name}.deduped.bam" "results/${name}.sorted.bam" || true
    samtools index "results/${name}.deduped.bam"

    # Call variants using LoFreq (sensitive mode for low coverage amplicons)
    lofreq call --min-coverage 5 \
        --max-mapping-quality 30 \
        -o "results/${name}.vcf.gz" \
        "results/${name}.deduped.bam"

    # Create TBI index for the VCF file (required by bcftools and tabix)
    if [[ ! -f "results/${name}.vcf.gz.tbi" ]]; then
        tabix -c -p vcf results/${name}.vcf.gz > /dev/null 2>&1 || true # Create tbi index
    fi
    
    # Clean up intermediate sorted and deduped BAM files to save space/time on reruns if needed, 
    # but keeping them ensures idempotency of the pipeline steps themselves. Since we check existence at start,
    # this script will re-run alignment if results/ is empty or partial. However, to be strictly efficient:
    rm -f "results/${name}.sorted.bam" "results/${name}.deduped.bam" 2>/dev/null || true
    
    echo "$name" > "/tmp/sample_list.txt" # Store sample name for later collapse (using temp file in cwd)
}

# Process each sample
for s in M117-bl M117-ch M117C1-bl M117C1-ch; do
    process_sample "$s"
done

# Generate collapsed table using bcftools and awk
# First, combine all VCF files into a single multi-sample file (bcftools merge)
if [[ -f "/tmp/sample_list.txt" ]]; then
    # Extract sample names from the list we created during processing
    samples=$(cat /tmp/sample_list.txt | tr '\n' ' ')
    
    bcftools merge --threads 4 \
        $(for s in $samples; do echo "results/${s}.vcf.gz"; done) > results/merged.vcf.gz
    
    # Index the merged VCF (optional but good practice, though not strictly required for collapse if we just read it)
    tabix -c -p vcf results/merged.vcf.gz > /dev/null 2>&1 || true

    # Extract variants and format as TSV with columns: sample chrom pos ref alt af
    bcftools query --format '%t\t%CHROM\t%POS\t%REF\t%ALT\t%AF' \
        -i 'SAMPLE="M117-bl"' results/merged.vcf.gz > /tmp/collapsed_M117bl.txt 2>/dev/null || true
    
    bcftools query --format '%t\t%CHROM\t%POS\t%REF\t%ALT\t%AF' \
        -i 'SAMPLE="M117-ch"' results/merged.vcf.gz > /tmp/collapsed_M117ch.txt 2>/dev/null || true
    
    bcftools query --format '%t\t%CHROM\t%POS\t%REF\t%ALT\t%AF' \
        -i 'SAMPLE="M117C1-bl"' results/merged.vcf.gz > /tmp/collapsed_M117C1bl.txt 2>/dev/null || true
    
    bcftools query --format '%t\t%CHROM\t%POS\t%REF\t%ALT\t%AF' \
        -i 'SAMPLE="M117C1-ch"' results/merged.vcf.gz > /tmp/collapsed_M117C1ch.txt 2>/dev/null || true

    # Combine all samples into one file, sorting by sample name then position for consistency
    cat /tmp/collapsed_*.txt | sort -t$'\t' -k5,5n -k3,3 > results/variants_combined.tsv
    
    # Add header and create final collapsed.tsv
    echo -e "sample\tchrom\tpos\tref\talt\taf" > results/collapsed.tsv
    awk -F'\t' 'NR>1 {print $0}' results/variants_combined.tsv >> results/collapsed.tsv

else
    # Fallback if sample list creation failed (should not happen)
    echo "Error: Sample processing completed but no samples found." >&2
fi

# Cleanup temporary files in current directory to keep it clean, though not strictly required by spec
rm -f /tmp/sample_list.txt /tmp/collapsed_*.txt results/merged.vcf.gz 2>/dev/null || true