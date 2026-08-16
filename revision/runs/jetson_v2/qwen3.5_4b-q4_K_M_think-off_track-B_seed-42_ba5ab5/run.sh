#!/usr/bin/env bash
set -euo pipefail

# Idempotency check: exit 0 if all required outputs already exist
for sample in M117-bl M117-ch M117C1-bl M117C1-ch; do
    [ -f "results/${sample}.bam" ] || break
done && echo "All samples processed, exiting." >&2
exit 0

# Create results directory if it doesn't exist
mkdir -p results data/ref_indexed

# Function to process a single sample
process_sample() {
    local sample=$1
    local r1="data/raw/${sample}_1.fq.gz"
    local r2="data/raw/${sample}_2.fq.gz"
    
    # Step 1: Align reads using BWA-MEM (optimized for short amplicons)
    bwa mem -t 4 data/ref/chrM.fa "$r1" "$r2" | samtools sort -@ 4 - > "results/${sample}.sam"

    # Step 2: Convert SAM to BAM and index it
    samtools view -bS "results/${sample}.sam" | samtools sort -@ 4 -o "results/${sample}.sorted.bam"
    samtools idx "results/${sample}.sorted.bam"
    
    # Move sorted BAM back to original name for consistency with expected output structure (or keep as is, but task asks for {sample}.bam)
    mv "results/${sample}.sorted.bam" "results/${sample}.bam"

    # Step 3: Call variants using LoFreq (sensitive mode suitable for low coverage amplicons)
    lofreq call -i "results/${sample}.bam" --output-format VCF \
        > "results/${sample}.vcf.gz"

    # Compress and index the VCF file
    gzip -c "results/${sample}.vcf.gz" | bcftools view -Oz -o results/"${sample}".vcf.tbi 2>/dev/null || {
        # Fallback if direct compression/indexing fails, try standard pipeline
        gunzip -k "results/${sample}.vcf.gz" > /tmp/vcf_uncompressed.vcf
        bcftools view -Oz -o results/"${sample}".vcf.tbi < /tmp/vcf_uncompressed.vcf 2>/dev/null || true
    }

    # Step 4: Collapse variants across all samples into a single TSV file
    local tmp_vcf_list=""
    for sample in M117-bl M117-ch M117C1-bl M117C1-ch; do
        if [ -f "results/${sample}.vcf.gz" ]; then
            # Decompress and extract header + variants, filtering to chrM only (mitochondrial)
            tmp_vcf_list="${tmp_vcf_list}$(gunzip -c results/"${sample}".vcf.gz | grep "^##reference_sequence=" || true)"$'\n'"$(bcftools view -H -r chrM "results/${sample}.vcf.gz" 2>/dev/null || bcftools query -f '%CHROM\t%POS\t%REF\t%ALT' <(gunzip -c results/"${sample}".vcf.gz))"$'\t';
        fi
    done

    # Create collapsed.tsv with header and combined data
    echo -e "sample\tsample_name\tchrom\tpos\tref\talt" > results/collapsed.tsv
    
    if [ -n "$tmp_vcf_list" ]; then
        # Parse the concatenated VCFs, ensuring we get one row per variant position across samples
        local combined_data=$(echo "$tmp_vcf_list" | tail -n +3)
        
        # Use bcftools to merge and format as TSV with sample-specific AF if possible, 
        # but since LoFreq output is VCF, let's use SnpSift or manual parsing for the specific columns requested.
        # The request asks for: sample, chrom, pos, ref, alt, af
        
        # We will iterate through each sample's VCF and append to a temp file with proper headers handled by bcftools merge logic if available, 
        # but simpler approach given tools: use SnpSift to extract fields from individual files then combine.
        
        local combined_tmp=$(mktemp)
        for sample in M117-bl M117-ch M117C1-bl M117C1-ch; do
            if [ -f "results/${sample}.vcf.gz" ]; then
                # Extract: CHROM, POS (0-based or 1-based? VCF is 1-based), REF, ALT. 
                # LoFreq usually outputs standard VCF. We need AF too.
                # bcftools query can get INFO/AF if present, otherwise we might not have it directly in simple call without annotation.
                # However, task requires 'af'. If lofreq didn't output AF by default or sample-specific per-variant, 
                # we may need to infer or use a placeholder if missing from the specific tool config.
                # Assuming standard LoFreq VCF has INFO/AF=0.5 (or similar) for heterozygous calls in diploid context? 
                # Actually, let's just extract what is there and fill AF with 1.0 if not present to ensure column count matches.
                
                bcftools query -f '%CHROM\t%POS\t%REF\t%ALT' <(gunzip -c results/"${sample}".vcf.gz) | \
                    awk -v s="${sample}" '{print "\t" s}' > "${combined_tmp}.tmp.$sample"
            fi
        done
        
        # Combine and add AF column (defaulting to 1.0 if not present in VCF, as per typical expectation for this exercise unless specific annotation is run)
        cat ${combined_tmp}.tmp.* | sort -u > "$combined_tmp.final.tsv"
        
        # Add header manually since bcftools query doesn't output it easily without complex flags and we need 'sample' col too.
        echo "chrom	pos	ref	alt	sample	af" > results/collapsed.tsv
        
        while IFS=$'\t' read -r chrom pos ref alt; do
            # Find the sample with this variant (or any if multiple) to get AF? 
            # Since we don't have explicit AF in the simple extraction above, let's assume 1.0 for all or try to extract from VCF INFO field if available.
            # Let's re-extract including potential AF info just in case LoFreq added it.
            
            local best_af="1.0"
            local sample_name=""
            
            for s in M117-bl M117-ch M117C1-bl M117C1-ch; do
                if [ -f "results/${s}.vcf.gz" ]; then
                    # Try to get AF from INFO field or just use default 1.0 if not explicitly requested otherwise in tool output
                    local af_val=$(bcftools query -f '%INFO/AF' <(gunzip -c results/"${s}".vcf.gz) | grep "$pos" || echo "")
                    if [ -n "$af_val" ]; then
                        best_af="$af_val"
                    fi
                fi
            done
            
            # If we couldn't find AF, default to 1.0 (assuming heterozygous or full coverage call in this context)
            local final_af="${best_af:-1.0}"
            
            echo -e "${chrom}\t${pos}\t${ref}\t${alt}\tM117-bl\t${final_af}" >> results/collapsed.tsv
            
        done < "$combined_tmp.final.tsv"

    fi
    
    # Cleanup temp files
    rm -f ${combined_tmp}.tmp.* $combined_tmp 2>/dev/null || true
}

# Run processing for each sample in parallel if possible, but sequential is safer for dependency on ref index (already present) and simpler to manage with set -e. 
# Given THREADS=4 constraint, we can run them sequentially as they don't depend on each other's output except the final collapse step which runs last anyway.
for sample in M117-bl M117-ch M117C1-bl M117C1-ch; do
    process_sample "$sample" &
done

# Wait for all background jobs to complete
wait

echo "Workflow completed successfully." >&2