#!/usr/bin/env bash
set -euo pipefail

# Ensure results directory exists (idempotent)
mkdir -p results/

# Define reference path relative to cwd
REF_FILE="data/ref/chrM.fa"

# Function to check if output already exists and skip processing
check_output() {
    local sample="$1"
    local bam_out="${results}/${sample}.bam"
    
    # If BAM file doesn't exist, process it; otherwise return success (idempotent)
    [[ ! -f "$bam_out" ]] || true
    
    if [[ -f "${bam_out%.bam}.bai" ]]; then
        return 0
    fi

    local sample_1="${sample}_1.fq.gz"
    local sample_2="${sample}_2.fq.gz"
    
    # Step 1: Alignment with BWA-MEM (using mem for speed on MiSeq data)
    bwa mem -t 4 "$REF_FILE" "${sample_1}" "${sample_2}" | \
        samtools sort -@ 4 -o "${bam_out}.sorted.bam"

    # Step 2: Index the BAM file and remove duplicates (optional but good practice for variant calling)
    # Since we are using lofreq which handles basic dedup or if not needed, we proceed to indexing.
    samtools index "${bam_out}.sorted.bam"
    
    # Move sorted bam to final location with correct name
    mv "${bam_out}.sorted.bam" "$bam_out"

# Step 3: Variant calling using lofreq (requires a VCF header)
call_variants() {
    local sample="$1"
    local ref_name="chrM"
    
    # Create minimal BCF/VCF header for lofreq if missing, or let it detect. 
    # LoFreq usually adds its own headers but we need to ensure the reference name is set correctly in bcftools context later.
    # We will use bcftools call with -m 1 (haploid) since mitochondrial DNA is haploid per cell/organism line, though lofreq handles it well too.
    
    local vcf_out="${results}/${sample}.vcf.gz"
    
    # Run LoFreq to generate VCF and BCF files in one go if possible, or separate steps. 
    # LoFreq 2.x typically outputs a .bcf file which can be converted, but it also has --output-vcf option.
    lofreq call -r "$REF_FILE" \
                -i "${bam_out}" \
                -o "${results}/${sample}.vcf.gz.bcf" \
                --min-coverage 20 \
                --max-missing 1
    
    # Convert BCF to VCF and index it using bcftools (more robust for tabix)
    bcftools view -Oz -o "$vcf_out" "${results}/${sample}.vcf.gz.bcf"
    
    # Create TBI index file
    tabix -p vcf "$vcf_out"

# Step 4: Generate collapsed table using SnpSift and awk logic (or bcftools query)
generate_collapsed() {
    local ref_name="chrM"
    
    # Use bcftools to extract variants from all samples, then filter for mtDNA specific info if needed.
    # Since we have multiple VCFs, we can use bcftools isec or just concatenate and dedup keys (pos+ref+alt).
    # However, the task asks for a collapsed table with columns: sample, chrom, pos, ref, alt, af
    
    # Strategy: For each sample, extract variants. Combine them into one file per chromosome? 
    # No, simpler: Concatenate all VCFs (excluding headers), sort by position and reference/alt to group identical sites across samples.
    
    local tmp_dir="${results}/tmp"
    mkdir -p "$tmp_dir"

    # Extract variants from each sample's VCF into a tab-separated file with 'sample' column
    for s in M117-bl M117-ch M117C1-bl M117C1-ch; do
        bcftools query --format '%\t%s\t%CHROM\t%POS\t%REF\t%ALT\t%AF\n' \
            -i 'INFO/DP>0 and INFO/GQ>=30' # Filter low quality calls if desired, but keep all for now to be safe. 
            "${results}/${s}.vcf.gz" > "$tmp_dir/${s}_variants.tsv"
    done

    # Combine all variant lines into one big file (skip header which bcftools query didn't produce as it outputs TSV directly)
    cat "$tmp_dir"/*_variants.tsv | sort -k4,4n -k5,5 > "${results}/all_variants_sorted.tmp"

    # Now we need to group by position and reference/alt. 
    # Since the same site might have different AFs per sample, but for a "collapsed table", usually it means one row per unique (chrom,pos,ref,alt) combination across ALL samples?
    # Or does it mean aggregated stats? The prompt says: columns: sample chrom pos ref alt af. 
    # This implies multiple rows if the same site has different AFs in different samples OR just listing all observed calls with their respective sample and AF.
    
    # Re-reading "collapsed.tsv" definition: It likely means a table of unique variants found across ALL samples, perhaps aggregating or simply listing them once per (sample, variant) tuple? 
    # Given the columns include 'sample', it suggests we list every call made by any sample at that position.
    
    # Let's assume "collapsed" means removing duplicate rows where all fields are identical including sample and AF.
    # But if a site has different AFs in M1 vs C1, they should be distinct rows (different AF). 
    # If the intent is to show unique genomic positions regardless of sample, then 'sample' column would make no sense unless it's always one value? No, that contradicts columns.
    
    # Most logical interpretation: A list of all variant calls across samples, deduplicated only if ALL fields match (including AF). 
    # If two samples call the same site with different AFs, they are distinct rows.
    # We just need to ensure we don't have duplicate lines in the output file itself.

    sort -u "${results}/all_variants_sorted.tmp" > "${results}/collapsed.tsv"

    # Cleanup temp files (optional but keeps results clean)
    rm -f "$tmp_dir"/*_variants.tsv "${results}/all_variants_sorted.tmp" 2>/dev/null || true
    
    echo "Collapsed table generated: ${results}/collapsed.tsv" >&2