#!/usr/bin/env bash
set -euo pipefail

# Create results directory if it doesn't exist and clean up previous runs for idempotency
mkdir -p results
rm -f results/*.bam results/*.bai results/*.vcf.gz results/*.tbi results/collapsed.tsv

# Function to check if a file exists (idempotent: returns 0 even if missing)
file_exists() {
    [[ -e "$1" ]] && return 0 || return 1
}

# Define sample list and reference path
samples=(M117-bl M117-ch M117C1-bl M117C1-ch)
ref_file="data/ref/chrM.fa"

# Step 1: Index the reference genome once (idempotent check included)
if ! file_exists "results/chrM.fa.fai"; then
    samtools faidx "$ref_file" > results/chrM.fa.fai || exit 1
fi

# Arrays to store VCF paths for collapsing later
declare -a vcf_paths=()

for sample in "${samples[@]}"; do
    # Construct input filenames based on sample name (e.g., M117-bl -> M117-bl_1.fq.gz)
    read -r r1_name r2_name <<< "$(printf '%s_%s' "$sample" 1)"
    read -r c1_name c2_name <<< "$(printf '%s_%s' "$sample" 2)"

    # Full paths to raw files (relative to cwd, no absolute paths)
    fq_r1="data/raw/${r1_name}.fq.gz"
    fq_r2="data/raw/${c1_name}.fq.gz"
    
    # Check if input data exists before proceeding (idempotent: skip if missing without erroring on empty results dir logic later, but here we assume valid dataset)
    if ! file_exists "$fq_r1"; then
        echo "Error: Input files for sample $sample not found." >&2
        exit 1
    fi

    # Step 2a: Align reads to reference using BWA-MEM (idempotent check on BAM)
    bam_file="results/${sample}.bam"
    
    if ! file_exists "$bam_file"; then
        bwa mem -t 4 \
            --threads 4 \
            -M \
            -f SAM \
            "${ref_file}" \
            "$fq_r1" "$fq_r2" | \
            samtools view -bS > "$bam_file" || exit 1
        
        # Create index for BAM file (required by bcftools)
        if ! file_exists "${bam_file}.bai"; then
            samtools sort -@ 4 -o results/${sample}_sorted.bam "$bam_file" && \
            mv results/${sample}_sorted.bam "$bam_file" || exit 1
            
            # Re-index after sorting (BWA-MEM output is sorted by default usually, but explicit sort ensures order)
            samtools index "${bam_file}" || exit 1
        fi
    else
        # Ensure BAM and BAI exist if we just created the file above logic skipped it? 
        # Actually bwa mem outputs unsorted bam. We need to sort/index every time for bcftools consistency unless already done.
        # Let's re-sort and index to be safe, or check existence of bai first.
        if ! file_exists "${bam_file}.bai"; then
            samtools view -bS "$fq_r1" "$fq_r2" | \
                samtools sort -@ 4 -o results/${sample}_sorted.bam && \
                mv results/${sample}_sorted.bam "$bam_file" || exit 1
            
            # Re-index after sorting (BWA-MEM output is sorted by default usually, but explicit sort ensures order)
            samtools index "${bam_file}" || exit 1
        fi
    fi

    # Step 2b: Call variants using bcftools mpileup + call or lofreq
    # Using bcftools mpileup (deprecated in newer versions but available here as v1.21) combined with call is standard for older stacks, 
    # however 'bcftools call' works best with a VCF input from an aligner like GATK HaplotypeCaller or similar.
    # Since we have lofreq and bcftools 1.21:
    # Option A: samtools mpileup -> bcftools call (deprecated in favor of -f but still works)
    # Option B: Use 'bcftools call' directly on the BAM with a reference
    
    vcf_file="results/${sample}.vcf.gz"

    if ! file_exists "$vcf_file"; then
        # Generate VCF using bcftools mpileup and call (standard pipeline for this toolset)
        samtools mpileup -f "${ref_file}" \
            --threads 4 \
            -a \
            -r chrM:16569-16569 \
            "$bam_file" | \
            bcftools call -cvf -o - > results/${sample}.vcf || exit 1
        
        # Compress and index VCF (required for collapsed table)
        if ! file_exists "${vcf_file}"; then
            gzip -c results/${sample}.vcf > "$vcf_file" && \
            tabix -p vcf -C "chrM.fa.fai" -o "$vcf_file" || exit 1
            
            # Remove uncompressed temp VCF if it exists (from bcftools call output)
            rm -f results/${sample}.vcf
        fi
        
        # Ensure index is present on the compressed file
        tabix -p vcf -C "chrM.fa.fai" "$vcf_file" || exit 1
    else
        # If VCF exists, ensure it's indexed (idempotent)
        if ! file_exists "${vcf_file}.tbi"; then
            tabix -p vcf -C "chrM.fa.fai" "$vcf_file" || exit 1
        fi
    fi

    vcf_paths+=("$vcf_file")
done

# Step 3: Collapse all VCFs into a single TSV file (sample, chrom, pos, ref, alt, af)
collapsed_output="results/collapsed.tsv"

if ! file_exists "$collapsed_output"; then
    # Write header first
    printf "sample\tchrom\tpos\tref\talt\taf\n" > "$collapsed_output"

    for vcf in "${vcf_paths[@]}"; do
        if [[ -n "$vcf" ]]; then
            sample_name=$(basename "$vcf" .vcf.gz)
            
            # Extract header line to get the reference name (should be chrM or similar, but we need 'sample' column first)
            # bcftools output format: <header> \t<chrom>\t<pos>\t<ref>\t<alt>\t...
            # We want a custom TSV with columns: sample, chrom, pos, ref, alt, af
            
            # Use seqkit to filter and extract specific fields efficiently without bcftools view overhead if possible? 
            # Or use bcftools query which is robust.
            
            # Get header line (first line) of VCF
            vcf_header=$(head -n 1 "$vcf")
            
            # Parse sample name from filename to prepend in output row
            while IFS=$'\t' read -r chrom pos ref alt af; do
                if [[ -z "$chrom" ]]; then continue; fi
                
                printf "%s\t%s\t%s\t%s\t%s\t%s\n" \
                    "$sample_name" \
                    "$chrom" \
                    "$pos" \
                    "$ref" \
                    "$alt" \
                    "${af:-.}" 
            done < <(bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\n' --no-header "$vcf") >> "$collapsed_output"
        fi
    done
    
    # Ensure the final file is indexed if needed? No, TSV doesn't need tabix. 
fi

exit 0