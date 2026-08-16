#!/usr/bin/env bash
set -euo pipefail

# Create results directory if it does not exist
mkdir -p results

# Function to check for existing outputs and skip if all present
check_outputs() {
    local sample="$1"
    # Check if any output file exists for this sample in results/
    [[ -f "results/${sample}.bam.bai" ]] && return 0
}

# Process each sample
for sample_dir in M117-bl M117-ch M117C1-bl M117C1-ch; do
    # Construct filenames based on directory name (remove -bl/-ch suffix to get base)
    if [[ "$sample_dir" == *-bl ]]; then
        sample_base="${sample_dir%-*}"
    else
        sample_base="$sample_dir"
    fi
    
    fq_1="data/raw/${sample_dir}_1.fq.gz"
    fq_2="data/raw/${sample_dir}_2.fq.gz"
    
    # Check if outputs already exist for this sample (idempotency)
    check_outputs "$sample_base" && continue

    echo "Processing $sample_base..." >&2
    
    # Step 1: Align reads to reference using BWA-MEM
    bwa mem -t 4 data/ref/chrM.fa "$fq_1" "$fq_2" | samtools sort -@ 4 -o results/${sample_base}.sort.bam

    # Step 2: Index the sorted BAM file for fast random access (required by lofreq)
    samtools index -r results/${sample_base}.sort.bam
    
    # Step 3: Call variants using LoFreq with appropriate parameters for amplicon sequencing
    # Using --min-qual-score and --max-bad-reads-per-sample to ensure high confidence calls on short reads
    lofreq call \
        --bam-file results/${sample_base}.sort.bam \
        --output-format vcf.gz \
        --reference data/ref/chrM.fa \
        --threads 4 \
        --min-qual-score 30 \
        --max-bad-reads-per-sample 1.5 \
        > results/${sample_base}.vcf.gz

    # Step 4: Create the TBI (tabix index) for the VCF file
    tabix -p vcf results/${sample_base}.vcf.gz
    
done

# Generate collapsed.tsv from all individual sample VCFs
echo "Generating collapsed table..." >&2

{
    echo -e "sample\tchrom\tpos\tref\talt\taf"
    
    for sample_dir in M117-bl M117-ch M117C1-bl M117C1-ch; do
        if [[ "$sample_dir" == *-bl ]]; then
            sample_base="${sample_dir%-*}"
        else
            sample_base="$sample_dir"
        fi
        
        # Extract variants from the VCF file, filtering for mitochondrial region (chrM) and high quality
        bcftools view -r chrM results/${sample_base}.vcf.gz \
            | awk 'BEGIN{FS="\t"; OFS="\t"} $1!="#" && $3=="." {print}' \
            > /tmp/variants_${sample_base}_chrM.tsv
        
    done
    
    # Combine all variant tables, sort by sample then position, and deduplicate if needed (though bcftools usually handles this)
    cat results/M117-bl_chrM.tsv results/M117-ch_chrM.tsv results/M117C1-bl_chrM.tsv results/M117C1-ch_chrM.tsv | \
        sort -t$'\t' -k2,2n -k3,3 > /tmp/collapsed_sorted.tsv
    
    # Final cleanup of temporary files (optional but good practice)
    rm -f /tmp/variants_*.tsv /tmp/collapsed_sorted.tsv

done