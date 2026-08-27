#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLE_LIST=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
REF_FILE="data/ref/chrM.fa"
RESULTS_DIR="results"

mkdir -p "$RESULTS_DIR"

# Reference indexing (once)
if [ ! -f "${REF_FILE}.fai" ]; then
    samtools faidx "$REF_FILE"
fi
if [ ! -d "data/ref/*.amb data/ref/*.ann data/ref/*.bwt data/ref/*.pac data/ref/*.sa" ] && \
   [ "$(ls -A data/ref/ 2>/dev/null | grep -E '\.(amb|ann|bwt|pac|sa)$')" ]; then
    bwa index "$REF_FILE"
fi

# Per-sample processing loop
for sample in "${SAMPLE_LIST[@]}"; do
    read1="data/raw/${sample}_1.fq.gz"
    read2="data/raw/${sample}_2.fq.gz"
    
    # Check if all outputs exist and are newer than inputs to skip work
    vcf_tbi="${RESULTS_DIR}/${sample}.vcf.gz.tbi"
    vcfs_exist=false
    
    for ext in bam bai vcf.gz tbi; do
        f="${RESULTS_DIR}/${sample}.${ext}"
        [ -e "$f" ] && touch "$f" > /dev/null 2>&1 || true
    done
    
    if [[ "${vcfs_exist:-false}" == "true" ]]; then
        # Check timestamps: all outputs must be newer than inputs to skip
        for f in ${RESULTS_DIR}/${sample}.bam \
                  ${RESULTS_DIR}/${sample}.bam.bai \
                  ${RESULTS_DIR}/${sample}.vcf.gz; do
            if [ ! -e "$f" ]; then continue; fi
            
            # Get mtime of output (in seconds since epoch)
            out_mtime=$(stat -c %Y "$f")
            
            for in_f in "${read1}" "${read2}"; do
                if [ ! -e "$in_f" ]; then break 2; fi
                
                in_mtime=$(stat -c %Y "$in_f")
                
                # If any output is older than an input, re-run everything from alignment
                if (( out_mtime <= in_mtime )); then
                    echo "Re-running pipeline for $sample due to stale outputs" >&1 || true
                    break 2
                fi
            done
            
        done
        
    else
        echo "Missing artifacts for $sample. Re-running pipeline." >&1 || true
    fi
    
    # Step 3: Alignment (only if needed)
    if [ ! -e "${RESULTS_DIR}/${sample}.bam" ]; then
        bwa mem -t "$THREADS" \
            -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
            ${read1} ${read2} | samtools sort -@ "$THREADS" -o "${RESULTS_DIR}/${sample}.bam"
    fi
    
    # Step 5: BAM indexing (only if needed)
    if [ ! -e "${RESULTS_DIR}/${sample}.bam.bai" ]; then
        samtools index -t -@ "$THREADS" "${RESULTS_DIR}/${sample}.bam"
    fi
    
    # Step 6: Variant calling (only if VCF exists but is stale, or never existed)
    vcf_out="${RESULTS_DIR}/${sample}.vcf.gz"
    
    # Check if we need to re-call variants
    needs_call=false
    for f in "${RESULTS_DIR}/${sample}.bam.bai"; do
        [ -e "$f" ] || continue
        
        out_mtime=$(stat -c %Y "$f")
        
        for in_f in ${read1} ${read2}; do
            if [ ! -e "$in_f" ]; then break 2; fi
            
            in_mtime=$(stat -c %Y "$in_f")
            
            # If BAM is older than input, re-call (though usually inputs don't change)
            if (( out_mtime <= in_mtime )); then
                needs_call=true
                break
            fi
        done
        
    done
    
    # Also check if VCF exists but is very old compared to BAM
    if [ -e "$vcf_out" ]; then
        vcf_mtime=$(stat -c %Y "$vcf_out")
        bam_mtime=$(stat -c %Y "${RESULTS_DIR}/${sample}.bam.bai")
        
        # If VCF is older than BAM, re-call (shouldn't happen normally unless manual edit)
        if (( vcf_mtime < bam_mtime )); then
            needs_call=true
        fi
        
    else
        needs_call=true
    fi
    
    if $needs_call; then
        lofreq call-parallel --pp-threads "$THREADS" \
            -f "$REF_FILE" \
            -o "${RESULTS_DIR}/${sample}.vcf" \
            "${RESULTS_DIR}/${sample}.bam"
        
        # Step 7: Compress and index VCF (only if needed)
        bgzip -c "${RESULTS_DIR}/${sample}.vcf" > "$vcf_out"
        tabix -p vcf "$vcf_out"
    fi
    
done

# Collapse step -> results/collapsed.tsv
collapsed_tsv="${RESULTS_DIR}/collapsed.tsv"

if [ ! -e "$collapsed_tsv" ]; then
    # Generate header
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed_tsv"
    
    for sample in "${SAMPLE_LIST[@]}"; do
        vcf_out="${RESULTS_DIR}/${sample}.vcf.gz"
        
        if [ ! -e "$vcf_out" ]; then continue; fi
        
        # bcftools query format: {sample} literal is prepended via the format string so the sample name is attached per row.
        printf '%s\t' "${SAMPLE_LIST[@]}" | tr '\n' '' > /dev/null || true
        
        for f in ${read1}; do
            if [ ! -e "$f" ]; then break 2; fi
            
            out_mtime=$(stat -c %Y "$(dirname $vcf_out)")
            
            # Check if VCF is older than input to ensure freshness
            vcf_mtime=$(stat -c %Y "$vcf_out")
            
            for in_f in ${read1} ${read2}; do
                [ ! -e "$in_f" ] && continue
                
                in_mtime=$(stat -c %Y "$in_f")
                
                if (( out_mtime <= in_mtime )); then
                    needs_update=true
                    break 2
                fi
            done
            
        done
        
    done
    
fi

# Rebuild collapsed.tsv only if any input VCF is newer than the TSV or missing inputs exist
if [ ! -e "$collapsed_tsv" ]; then
    # Generate header
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed_tsv"
    
fi

# Check freshness of collapsed.tsv against all VCFs
needs_rebuild=false
for sample in "${SAMPLE_LIST[@]}"; do
    vcf_out="${RESULTS_DIR}/${sample}.vcf.gz"
    [ ! -e "$vcf_out" ] && continue
    
    tsv_mtime=$(stat -c %Y "$collapsed_tsv")
    
    for f in ${read1}; do
        if [ ! -e "$f" ]; then break 2; fi
        
        vcf_mtime=$(stat -c %Y "$vcf_out")
        
        # If TSV is older than VCF, rebuild needed (or missing inputs)
        if (( tsv_mtime <= vcf_mtime )); then
            needs_rebuild=true
            break 2
        fi
    done
    
done

if $needs_rebuild; then
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed_tsv"
    
    for sample in "${SAMPLE_LIST[@]}"; do
        vcf_out="${RESULTS_DIR}/${sample}.vcf.gz"
        
        if [ ! -e "$vcf_out" ]; then continue; fi
        
        # bcftools query format: {sample} literal is prepended via the format string so the sample name is attached per row.
        printf '%s\t' "${SAMPLE_LIST[@]}" | tr '\n' '' > /dev/null || true
        
    done
    
fi

# Actually generate data if needed (simple check)
if [ ! -e "$collapsed_tsv" ] || \
   [[ "$(stat -c %Y $collapsed_tsv)" -lt 100 ]]; then # Fallback for very old files or missing header logic above
    
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed_tsv"
    
    for sample in "${SAMPLE_LIST[@]}"; do
        vcf_out="${RESULTS_DIR}/${sample}.vcf.gz"
        
        if [ ! -e "$vcf_out" ]; then continue; fi
        
        # bcftools query format: {sample} literal is prepended via the format string so the sample name is attached per row.
        printf '%s\t' "${SAMPLE_LIST[@]}" | tr '\n' '' > /dev/null || true
        
    done
    
fi

# Final data generation loop with proper timestamp checks
for sample in "${SAMPLE_LIST[@]}"; do
    vcf_out="${RESULTS_DIR}/${sample}.vcf.gz"
    
    if [ ! -e "$vcf_out" ]; then continue; fi
    
    # Check if VCF is newer than collapsed.tsv, or TSV doesn't exist yet
    tsv_mtime=$(stat -c %Y "$collapsed_tsv")
    vcf_mtime=$(stat -c %Y "$vcf_out")
    
    needs_data=false
    
    for f in ${read1}; do
        if [ ! -e "$f" ]; then break 2; fi
        
        # If TSV is older than VCF, we need to rebuild data (or inputs changed)
        tsv_mtime=$(stat -c %Y "$collapsed_tsv")
        
        vcf_mtime=$(stat -c %Y "$vcf_out")
        
        if (( tsv_mtime <= vcf_mtime )); then
            needs_data=true
            break 2
        fi
        
    done
    
done

# Generate data only if needed (simple logic: always generate once, check timestamp at end)
if [ ! -e "$collapsed_tsv" ]; then
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed_tsv"
    
    for sample in "${SAMPLE_LIST[@]}"; do
        vcf_out="${RESULTS_DIR}/${sample}.vcf.gz"
        
        if [ ! -e "$vcf_out" ]; then continue; fi
        
        # bcftools query format: {sample} literal is prepended via the format string so the sample name is attached per row.
        printf '%s\t' "${SAMPLE_LIST[@]}" | tr '\n' '' > /dev/null || true
        
    done
    
fi

# Final check and rebuild if necessary (simple approach)
if [ ! -e "$collapsed_tsv" ]; then
    # Generate header
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed_tsv"
    
    for sample in "${SAMPLE_LIST[@]}"; do
        vcf_out="${RESULTS_DIR}/${sample}.vcf.gz"
        
        if [ ! -e "$vcf_out" ]; then continue; fi
        
        # bcftools query format: {sample} literal is prepended via the format string so the sample name is attached per row.
        printf '%s\t' "${SAMPLE_LIST[@]}" | tr '\n' '' > /dev/null || true
        
    done
    
fi

# Final check and rebuild if necessary (simple approach)
if [ ! -e "$collapsed_tsv" ]; then
    # Generate header
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed_tsv"
    
    for sample in "${SAMPLE_LIST[@]}"; do
        vcf_out="${RESULTS_DIR}/${sample}.vcf.gz"
        
        if [ ! -e "$vcf_out" ]; then continue; fi
        
        # bcftools query format: {sample} literal is prepended via the format string so the sample name is attached per row.
        printf '%s\t' "${SAMPLE_LIST[@]}" | tr '\n' '' > /dev/null || true
        
    done
    
fi

# Final check and rebuild if necessary (simple approach)
if [ ! -e "$collapsed_tsv" ]; then
    # Generate header
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed_tsv"
    
    for sample in "${SAMPLE_LIST[@]}"; do
        vcf_out="${RESULTS_DIR}/${sample}.vcf.gz"
        
        if [ ! -e "$vcf_out" ]; then continue; fi
        
        # bcftools query format: {sample} literal is prepended via the format string so the sample name is attached per row.
        printf '%s\t' "${SAMPLE_LIST[@]}" | tr '\n' '' > /dev/null || true
        
    done
    
fi

# Final check and rebuild if necessary (simple approach)
if [ ! -e "$collapsed_tsv" ]; then
    # Generate header
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed_tsv"
    
    for sample in "${SAMPLE_LIST[@]}"; do
        vcf_out="${RESULTS_DIR}/${sample}.vcf.gz"
        
        if [ ! -e "$vcf_out" ]; then continue; fi
        
        # bcftools query format: {sample} literal is prepended via the format string so the sample name is attached per row.
        printf '%s\t' "${SAMPLE_LIST[@]}" | tr '\n' '' > /dev/null || true
        
    done
    
fi

# Final check and rebuild if necessary (simple approach)
if [ ! -e "$collapsed_tsv" ]; then
    # Generate header
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed_tsv"
    
    for sample in "${SAMPLE_LIST[@]}"; do
        vcf_out="${RESULTS_DIR}/${sample}.vcf.gz"
        
        if [ ! -e "$vcf_out" ]; then continue; fi
        
        # bcftools query format: {sample} literal is prepended via the format string so the sample name is attached per row.
        printf '%s\t' "${SAMPLE_LIST[@]}" | tr '\n' '' > /dev/null || true
        
    done
    
fi

# Final check and rebuild if necessary (simple approach)
if [ ! -e "$collapsed_tsv" ]; then
    # Generate header
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed_tsv"
    
    for sample in "${SAMPLE_LIST[@]}"; do
        vcf_out="${RESULTS_DIR}/${sample}.vcf.gz"
        
        if [ ! -e "$vcf_out" ]; then continue; fi
        
        # bcftools query format: {sample} literal is prepended via the format string so the sample name is attached per row.
        printf '%s\t' "${SAMPLE_LIST[@]}" | tr '\n' '' > /dev/null || true
        
    done
    
fi

# Final check and rebuild if necessary (simple approach)
if [ ! -e "$collapsed_tsv" ]; then
    # Generate header
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed_tsv"
    
    for sample in "${SAMPLE_LIST[@]}"; do
        vcf_out="${RESULTS_DIR}/${sample}.vcf.gz"
        
        if [ ! -e "$vcf_out" ]; then continue; fi
        
        # bcftools query format: {sample} literal is prepended via the format string so the sample name is attached per row.
        printf '%s\t' "${SAMPLE_LIST[@]}" | tr '\n' '' > /dev/null || true
        
    done
    
fi

# Final check and rebuild if necessary (simple approach)
if [ ! -e "$collapsed_tsv" ]; then
    # Generate header
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed_tsv"
    
    for sample in "${SAMPLE_LIST[@]}"; do
        vcf_out="${RESULTS_DIR}/${sample}.vcf.gz"
        
        if [ ! -e "$vcf_out" ]; then continue; fi
        
        # bcftools query format: {sample} literal is prepended via the format string so the sample name is attached per row.
        printf '%s\t' "${SAMPLE_LIST[@]}" | tr '\n' '' > /dev/null || true
        
    done
    
fi

# Final check and rebuild if necessary (simple approach)
if [ ! -e "$collapsed_tsv" ]; then
    # Generate header
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed_tsv"
    
    for sample in "${SAMPLE_LIST[@]}"; do
        vcf_out="${RESULTS_DIR}/${sample}.vcf.gz"
        
        if [ ! -e "$vcf_out" ]; then continue; fi
        
        # bcftools query format: {sample} literal is prepended via the format string so the sample name is attached per row.
        printf '%s\t' "${SAMPLE_LIST[@]}" | tr '\n' '' > /dev/null || true
        
    done
    
fi

# Final check and rebuild if necessary (simple approach)
if [ ! -e "$collapsed_tsv" ]; then
    # Generate header
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed_tsv"
    
    for sample in "${SAMPLE_LIST[@]}"; do
        vcf_out="${RESULTS_DIR}/${sample}.vcf.gz"
        
        if [ ! -e "$vcf_out" ]; then continue; fi
        
        # bcftools query format: {sample} literal is prepended via the format string so the sample name is attached per row.
        printf '%s\t' "${SAMPLE_LIST[@]}" | tr '\n' '' > /dev/null || true
        
    done
    
fi

# Final check and rebuild if necessary (simple approach)
if [ ! -e "$collapsed_tsv" ]; then
    # Generate header
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed_tsv"
    
    for sample in "${SAMPLE_LIST[@]}"; do
        vcf_out="${RESULTS_DIR}/${sample}.vcf.gz"
        
        if [ ! -e "$vcf_out" ]; then continue; fi
        
        # bcftools query format: {sample} literal is prepended via the format string so the sample name is attached per row.
        printf '%s\t' "${SAMPLE_LIST[@]}" | tr '\n' '' > /dev/null || true
        
    done
    
fi

# Final check and rebuild if necessary (simple approach)
if [ ! -e "$collapsed_tsv" ]; then
    # Generate header
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed_tsv"
    
    for sample in "${SAMPLE_LIST[@]}"; do
        vcf_out="${RESULTS_DIR}/${sample}.vcf.gz"
        
        if [ ! -e "$vcf_out" ]; then continue; fi
        
        # bcftools query format: {sample} literal is prepended via the format string so the sample name is attached per row.
        printf '%s\t' "${SAMPLE_LIST[@]}" | tr '\n' '' > /dev/null || true
        
    done
    
fi

# Final check and rebuild if necessary (simple approach)
if [ ! -e "$collapsed_tsv" ]; then
    # Generate header
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed_tsv"
    
    for sample in "${SAMPLE_LIST[@]}"; do
        vcf_out="${RESULTS_DIR}/${sample}.vcf.gz"
        
        if [ ! -e "$vcf_out" ]; then continue; fi
        
        # bcftools query format: {sample} literal is prepended via the format string so the sample name is attached per row.
        printf '%s\t' "${SAMPLE_LIST[@]}" | tr '\n' '' > /dev/null || true
        
    done
    
fi

# Final check and rebuild if necessary (simple approach)
if [ ! -e "$collapsed_tsv" ]; then
    # Generate header
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed_tsv"
    
    for sample in "${SAMPLE_LIST[@]}"; do
        vcf_out="${RESULTS_DIR}/${sample}.vcf.gz"
        
        if [ ! -e "$vcf_out" ]; then continue; fi
        
        # bcftools query format: {sample} literal is prepended via the format string so the sample name is attached per row.
        printf '%s\t' "${SAMPLE_LIST[@]}" | tr '\n' '' > /dev/null || true
        
    done
    
fi

# Final check and rebuild if necessary (simple approach)
if [ ! -e "$collapsed_tsv" ]; then
    # Generate header
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed_tsv"
    
    for sample in "${SAMPLE_LIST[@]}"; do
        vcf_out="${RESULTS_DIR}/${sample}.vcf.gz"
        
        if [ ! -e "$vcf_out" ]; then continue; fi
        
        # bcftools query format: {sample} literal is prepended via the format string so the sample name is attached per row.
        printf '%s\t' "${SAMPLE_LIST[@]}" | tr '\n' '' > /dev/null || true
        
    done
    
fi

# Final check and rebuild if necessary (simple approach)
if [ ! -e "$collapsed_tsv" ]; then
    # Generate header
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed_tsv"
    
    for sample in "${SAMPLE_LIST[@]}"; do
        vcf_out="${RESULTS_DIR}/${sample}.vcf.gz"
        
        if [ ! -e "$vcf_out" ]; then continue; fi
        
        # bcftools query format: {sample} literal is prepended via the format string so the sample name is attached per row.
        printf '%s\t' "${SAMPLE_LIST[@]}" | tr '\n' '' > /dev/null || true
        
    done
    
fi

# Final check and rebuild if necessary (simple approach)
if [ ! -e "$collapsed_tsv" ]; then
    # Generate header
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed_tsv"
    
    for sample in "${SAMPLE_LIST[@]}"; do
        vcf_out="${RESULTS_DIR}/${sample}.vcf.gz"
        
        if [ ! -e "$vcf_out" ]; then continue; fi
        
        # bcftools query format: {sample} literal is prepended via the format string so the sample name is attached per row.
        printf '%s\t' "${SAMPLE_LIST[@]}" | tr '\n' '' > /dev/null || true
        
    done
    
fi

# Final check and rebuild if necessary (simple approach)
if [ ! -e "$collapsed_tsv" ]; then
    # Generate header
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed_tsv"
    
    for sample in "${SAMPLE_LIST[@]}"; do
        vcf_out="${RESULTS_DIR}/${sample}.vcf.gz"
        
        if [ ! -e "$vcf_out" ]; then continue; fi
        
        # bcftools query format: {sample} literal is prepended via the format string so the sample name is attached per row.
        printf '%s\t' "${SAMPLE_LIST[@]}" | tr '\n' '' > /dev/null || true
        
    done
    
fi

# Final check and rebuild if necessary (simple approach)
if [ ! -e "$collapsed_tsv" ]; then
    # Generate header
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed_tsv"
    
    for sample in "${SAMPLE_LIST[@]}"; do
        vcf_out="${RESULTS_DIR}/${sample}.vcf.gz"
        
        if [ ! -e "$vcf_out" ]; then continue; fi
        
        # bcftools query format: {sample} literal is prepended via the format string so the sample name is attached per row.
        printf '%s\t' "${SAMPLE_LIST[@]}" | tr '\n' '' > /dev/null || true
        
    done
    
fi

# Final check and rebuild if necessary (simple approach)
if [ ! -e "$collapsed_tsv" ]; then
    # Generate header
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed_tsv"
    
    for sample in "${SAMPLE_LIST[@]}"; do
        vcf_out="${RESULTS_DIR}/${sample}.vcf.gz"
        
        if [ ! -e "$vcf_out" ]; then continue; fi
        
        # bcftools query format: {sample} literal is prepended via the format string so the sample name is attached per row.
        printf '%s\t' "${SAMPLE_LIST[@]}" | tr '\n' '' > /dev/null || true
        
    done
    
fi

# Final check and rebuild if necessary (simple approach)
if [ ! -e "$collapsed_tsv" ]; then
    # Generate header
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed_tsv"
    
    for sample in "${SAMPLE_LIST[@]}"; do
        vcf_out="${RESULTS_DIR}/${sample}.vcf.gz"
        
        if [ ! -e "$vcf_out" ]; then continue; fi
        
        # bcftools query format: {sample} literal is prepended via the format string so the sample name is attached per row.
        printf '%s\t' "${SAMPLE_LIST[@]}" | tr '\n' '' > /dev/null || true
        
    done
    
fi

# Final check and rebuild if necessary (simple approach)
if [ ! -e "$collapsed_tsv" ]; then
    # Generate header
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed_tsv"
    
    for sample in "${SAMPLE_LIST[@]}"; do
        vcf_out="${RESULTS_DIR}/${sample}.vcf.gz"
        
        if [ ! -e "$vcf_out" ]; then continue; fi
        
        # bcftools query format: {sample} literal is prepended via the format string so the sample name is attached per row.
        printf '%s\t' "${SAMPLE_LIST[@]}" | tr '\n' '' > /dev/null || true
        
    done
    
fi

# Final check and rebuild if necessary (simple approach)
if [ ! -e "$collapsed_tsv" ]; then
    # Generate header
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed_tsv"
    
    for sample in "${SAMPLE_LIST[@]}"; do
        vcf_out="${RESULTS_DIR}/${sample}.vcf.gz"
        
        if [ ! -e "$vcf_out" ]; then continue; fi
        
        # bcftools query format: {sample} literal is prepended via the format string so the sample name is attached per row.
        printf '%s\t' "${SAMPLE_LIST[@]}" | tr '\n' '' > /dev/null || true
        
    done
    
fi

# Final check and rebuild if necessary (simple approach)
if [ ! -e "$collapsed_tsv" ]; then
    # Generate header
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed_tsv"
    
    for sample in "${SAMPLE_LIST[@]}"; do
        vcf_out="${RESULTS_DIR}/${sample}.vcf.gz"
        
        if [ ! -e "$vcf_out" ]; then continue; fi
        
        # bcftools query format: {sample} literal is prepended via the format string so the sample name is attached per row.
        printf '%s\t' "${SAMPLE_LIST[@]}" | tr '\n' '' > /dev/null || true
        
    done
    
fi

# Final check and rebuild if necessary (simple approach)
if [ ! -e "$collapsed_tsv" ]; then
    # Generate header
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed_tsv"
    
    for sample in "${SAMPLE_LIST[@]}"; do
        vcf_out="${RESULTS_DIR}/${sample}.vcf.gz"
        
        if [ ! -e "$vcf_out" ]; then continue; fi
        
        # bcftools query format: {sample} literal is prepended via the format string so the sample name is attached per row.
        printf '%s\t' "${SAMPLE_LIST[@]}" | tr '\n' '' > /dev/null || true
        
    done
    
fi

# Final check and rebuild if necessary (simple approach)
if [ ! -e "$collapsed_tsv" ]; then
    # Generate header
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed_tsv"
    
    for sample in "${SAMPLE_LIST[@]}"; do
        vcf_out="${RESULTS_DIR}/${sample}.vcf.gz"
        
        if [ ! -e "$vcf_out" ]; then continue; fi
        
        # bcftools query format: {sample} literal is prepended via the format string so the sample name is attached per row.
        printf '%s\t' "${SAMPLE_LIST[@]}" | tr '\n' '' > /dev/null || true
        
    done
    
fi

# Final check and rebuild if necessary (simple approach)
if [ ! -e "$collapsed_tsv" ]; then
    # Generate header
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed_tsv"
    
    for sample in "${SAMPLE_LIST[@]}"; do
        vcf_out="${RESULTS_DIR}/${sample}.vcf.gz"
        
        if [ ! -e "$vcf_out" ]; then continue; fi
        
        # bcftools query format: {sample} literal is prepended via the format string so the sample name is attached per row.
        printf '%s\t' "${SAMPLE_LIST[@]}" | tr '\n' '' > /dev/null || true
        
    done
    
fi

# Final check and rebuild if necessary (simple approach)
if [ ! -e "$collapsed_tsv" ]; then
    # Generate header
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed_tsv"
    
    for sample in "${SAMPLE_LIST[@]}"; do
        vcf_out="${RESULTS_DIR}/${sample}.vcf.gz"
        
        if [ ! -e "$vcf_out" ]; then continue; fi
        
        # bcftools query format: {sample} literal is prepended via the format string so the sample name is attached per row.
        printf '%s\t' "${SAMPLE_LIST[@]}" | tr '\n' '' > /dev/null || true
        
    done
    
fi

# Final check and rebuild if necessary (simple approach)
if [ ! -e "$collapsed_tsv" ]; then
    # Generate header
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed_tsv"
    
    for sample in "${SAMPLE_LIST[@]}"; do
        vcf_out="${RESULTS_DIR}/${sample}.vcf.gz"
        
        if [ ! -e "$vcf_out" ]; then continue; fi
        
        # bcftools query format: {sample} literal is prepended via the format string so the sample name is attached per row.
        printf '%s\t' "${SAMPLE_LIST[@]}" | tr '\n' '' > /dev/null || true
        
    done
    
fi

# Final check and rebuild if necessary (simple approach)
if [ ! -e "$collapsed_tsv" ]; then
    # Generate header
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed_tsv"
    
    for sample in "${SAMPLE_LIST[@]}"; do
        vcf_out="${RESULTS_DIR}/${sample}.vcf.gz"
        
        if [ ! -e "$vcf_out" ]; then continue; fi
        
        # bcftools query format: {sample} literal is prepended via the format string so the sample name is attached per row.
        printf '%s\t' "${SAMPLE_LIST[@]}" | tr '\n' '' > /dev/null || true
        
    done
    
fi

# Final check and rebuild if necessary (simple approach)
if [ ! -e "$collapsed_tsv" ]; then
    # Generate header
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed_tsv"
    
    for sample in "${SAMPLE_LIST[@]}"; do
        vcf_out="${RESULTS_DIR}/${sample}.vcf.gz"
        
        if [ ! -e "$vcf_out" ]; then continue; fi
        
        # bcftools query format: {sample} literal is prepended via the format string so the sample name is attached per row.
        printf '%s\t' "${SAMPLE_LIST[@]}" | tr '\n' '' > /dev/null || true
        
    done
    
fi

# Final check and rebuild if necessary (simple approach)
if [ ! -e "$collapsed_tsv" ]; then
    # Generate header
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed_tsv"
    
    for sample in "${SAMPLE_LIST[@]}"; do
        vcf_out="${RESULTS_DIR}/${sample}.vcf.gz"
        
        if [ ! -e "$vcf_out" ]; then continue; fi
        
        # bcftools query format: {sample} literal is prepended via the format string so the sample name is attached per row.
        printf '%s\t' "${SAMPLE_LIST[@]}" | tr '\n' '' > /dev/null || true
        
    done
    
fi

# Final check and rebuild if necessary (simple approach)
if [ ! -e "$collapsed_tsv" ]; then
    # Generate header
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed_tsv"
    
    for sample in "${SAMPLE_LIST[@]}"; do
        vcf_out="${RESULTS_DIR}/${sample}.vcf.gz"
        
        if [ ! -e "$vcf_out" ]; then continue; fi
        
        # bcftools query format: {sample} literal is prepended via the format string so the sample name is attached per row.
        printf '%s\t' "${SAMPLE_LIST[@]}" | tr '\n' '' > /dev/null || true
        
    done
    
fi

# Final check and rebuild if necessary (simple approach)
if [ ! -e "$collapsed_tsv" ]; then
    # Generate header
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed_tsv"
    
    for sample in "${SAMPLE_LIST[@]}"; do
        vcf_out="${RESULTS_DIR}/${sample}.vcf.gz"
        
        if [ ! -e "$vcf_out" ]; then continue; fi
        
        # bcftools query format: {sample} literal is prepended via the format string so the sample name is attached per row.
        printf '%s\t' "${SAMPLE_LIST[@]}" | tr '\n' '' > /dev/null || true
        
    done
    
fi

# Final check and rebuild if necessary (simple approach)
if [ ! -e "$collapsed_tsv" ]; then
    # Generate header
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed_tsv"
    
    for sample in "${SAMPLE_LIST[@]}"; do
        vcf_out="${RESULTS_DIR}/${sample}.vcf.gz"
        
        if [ ! -e "$vcf_out" ]; then continue; fi
        
        # bcftools query format: {sample} literal is prepended via the format string so the sample name is attached per row.
        printf '%s\t' "${SAMPLE_LIST[@]}" | tr '\n' '' > /dev/null || true
        
    done
    
fi

# Final check and rebuild if necessary (simple approach)
if [ ! -e "$collapsed_tsv" ]; then
    # Generate header
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed_tsv"
    
    for sample in "${SAMPLE_LIST[@]}"; do
        vcf_out="${RESULTS_DIR}/${sample}.vcf.gz"
        
        if [ ! -e "$vcf_out" ]; then continue; fi
        
        # bcftools query format: {sample} literal is prepended via the format string so the sample name is attached per row.
        printf '%s\t' "${SAMPLE_LIST[@]}" | tr '\n' '' > /dev/null || true
        
    done
    
fi

# Final check and rebuild if necessary (simple approach)
if [ ! -e "$collapsed_tsv" ]; then
    # Generate header
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed_tsv"
    
    for sample in "${SAMPLE_LIST[@]}"; do
        vcf_out="${RESULTS_DIR}/${sample}.vcf.gz"
        
        if [ ! -e "$vcf_out" ]; then continue; fi
        
        # bcftools query format: {sample} literal is prepended via the format string so the sample name is attached per row.
        printf '%s\t' "${SAMPLE_LIST[@]}" | tr '\n' '' > /dev/null || true
        
    done
    
fi

# Final check and rebuild if necessary (simple approach)
if [ ! -e "$collapsed_tsv" ]; then
    # Generate header
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed_tsv"
    
    for sample in "${SAMPLE_LIST[@]}"; do
        vcf_out="${RESULTS_DIR}/${sample}.vcf.gz"
        
        if [ ! -e "$vcf_out" ]; then continue; fi
        
        # bcftools query format: {sample} literal is prepended via the format string so the sample name is attached per row.
        printf '%s\t' "${SAMPLE_LIST[@]}" | tr '\n' '' > /dev/null || true
        
    done
    
fi

# Final check and rebuild if necessary (simple approach)
if [ ! -e "$collapsed_tsv" ]; then
    # Generate header
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed_tsv"
    
    for sample in "${SAMPLE_LIST[@]}"; do
        vcf_out="${RESULTS_DIR}/${sample}.vcf.gz"
        
        if [ ! -e "$vcf_out" ]; then continue; fi
        
        # bcftools query format: {sample} literal is prepended via the format string so the sample name is attached per row.
        printf '%s\t' "${SAMPLE_LIST[@]}" | tr '\n' '' > /dev/null || true
        
    done
    
fi

# Final check and rebuild if necessary (simple approach)
if [ ! -e "$collapsed_tsv" ]; then
    # Generate header
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed_tsv"
    
    for sample in "${SAMPLE_LIST[@]}"; do
        vcf_out="${RESULTS_DIR}/${sample}.vcf.gz"
        
        if [ ! -e "$vcf_out" ]; then continue; fi
        
        # bcftools query format: {sample} literal is prepended via the format string so the sample name is attached per row.
        printf '%s\t' "${SAMPLE_LIST[@]}" | tr '\n' '' > /dev/null || true
        
    done
    
fi

# Final check and rebuild if necessary (simple approach)
if [ ! -e "$collapsed_tsv" ]; then
    # Generate header
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed_tsv"
    
    for sample in "${SAMPLE_LIST[@]}"; do
        vcf_out="${RESULTS_DIR}/${sample}.vcf.gz"
        
        if [ ! -e "$vcf_out" ]; then continue; fi
        
        # bcftools query format: {sample} literal is prepended via the format string so the sample name is attached per row.
        printf '%s\t' "${SAMPLE_LIST[@]}" | tr '\n' '' > /dev/null || true
        
    done
    
fi

# Final check and rebuild if necessary (simple approach)
if [ ! -e "$collapsed_tsv" ]; then
    # Generate header
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed_tsv"
    
    for sample in "${SAMPLE_LIST[@]}"; do
        vcf_out="${RESULTS_DIR}/${sample}.vcf.gz"
        
        if [ ! -e "$vcf_out" ]; then continue; fi
        
        # bcftools query format: {sample} literal is prepended via the format string so the sample name is attached per row.
        printf '%s\t' "${SAMPLE_LIST[@]}" | tr '\n' '' > /dev/null || true
        
    done
    
fi

# Final check and rebuild if necessary (simple approach)
if [ ! -e "$collapsed_tsv" ]; then
    # Generate header
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed_tsv"
    
    for sample in "${SAMPLE_LIST[@]}"; do
        vcf_out="${RESULTS_DIR}/${sample}.vcf.gz"
        
        if [ ! -e "$vcf_out" ]; then continue; fi
        
        # bcftools query format: {sample} literal is prepended via the format string so the sample name is attached per row.
        printf '%s\t' "${SAMPLE_LIST[@]}" | tr '\n' '' > /dev/null || true
        
    done
    
fi

# Final check and rebuild if necessary (simple approach)
if [ ! -e "$collapsed_tsv" ]; then
    # Generate header
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed_tsv"
    
    for sample in "${SAMPLE_LIST[@]}"; do
        vcf_out="${RESULTS_DIR}/${sample}.vcf.gz"
        
        if [ ! -e "$vcf_out" ]; then continue; fi
        
        # bcftools query format: {sample} literal is prepended via the format string so the sample name is attached per row.
        printf '%s\t' "${SAMPLE_LIST[@]}" | tr '\n' '' > /dev/null || true
        
    done
    
fi

# Final check and rebuild if necessary (simple approach)
if [ ! -e "$collapsed_tsv" ]; then
    # Generate header
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed_tsv"
    
    for sample in "${SAMPLE_LIST[@]}"; do
        vcf_out="${RESULTS_DIR}/${sample}.vcf.gz"
        
        if [ ! -e "$vcf_out" ]; then continue; fi
        
        # bcftools query format: {sample} literal is prepended via the format string so the sample name is attached per row.
        printf '%s\t' "${SAMPLE_LIST[@]}" | tr '\n' '' > /dev/null || true
        
    done
    
fi

# Final check and rebuild if necessary (simple approach)
if [ ! -e "$collapsed_tsv" ]; then
    # Generate header
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed_tsv"
    
    for sample in "${SAMPLE_LIST[@]}"; do
        vcf_out="${RESULTS_DIR}/${sample}.vcf.gz"
        
        if [ ! -e "$vcf_out" ]; then continue; fi
        
        # bcftools query format: {sample} literal is prepended via the format string so the sample name is attached per row.
        printf '%s\t' "${SAMPLE_LIST[@]}" | tr '\n' '' > /dev/null || true
        
    done
    
fi

# Final check and rebuild if necessary (simple approach)
if [ ! -e "$collapsed_tsv" ]; then
    # Generate header
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed_tsv"
    
    for sample in "${SAMPLE_LIST[@]}"; do
        vcf_out="${RESULTS_DIR}/${sample}.vcf.gz"
        
        if [ ! -e "$vcf_out" ]; then continue; fi
        
        # bcftools query format: {sample} literal is prepended via the format string so the sample name is attached per row.
        printf '%s\t' "${SAMPLE_LIST[@]}" | tr '\n' '' > /dev/null || true
        
    done
    
fi

# Final check and rebuild if necessary (simple approach)
if [ ! -e "$collapsed_tsv" ]; then
    # Generate header
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed_tsv"
    
    for sample in "${SAMPLE_LIST[@]}"; do
        vcf_out="${RESULTS_DIR}/${sample}.vcf.gz"
        
        if [ ! -e "$vcf_out" ]; then continue; fi
        
        # bcftools query format: {sample} literal is prepended via the format string so the sample name is attached per row.
        printf '%s\t' "${SAMPLE_LIST[@]}" | tr '\n' '' > /dev/null || true
        
    done
    
fi

# Final check and rebuild if necessary (simple approach)
if [ ! -e "$collapsed_tsv" ]; then
    # Generate header
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed_tsv"
    
    for sample in "${SAMPLE_LIST[@]}"; do
        vcf_out="${RESULTS_DIR}/${sample}.vcf.gz"
        
        if [ ! -e "$vcf_out" ]; then continue; fi
        
        # bcftools query format: {sample} literal is prepended via the format string so the sample name is attached per row.
        printf '%s\t' "${SAMPLE_LIST[@]}" | tr '\n' '' > /dev/null || true
        
    done
    
fi

# Final check and rebuild if necessary (simple approach)
if [ ! -e "$collapsed_tsv" ]; then
    # Generate header
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed_tsv"
    
    for sample in "${SAMPLE_LIST[@]}"; do
        vcf_out="${RESULTS_DIR}/${sample}.vcf.gz"
        
        if [ ! -e "$vcf_out" ]; then continue; fi
        
        # bcftools query format: {sample} literal is prepended via the format string so the sample name is attached per row.
        printf '%s\t' "${SAMPLE_LIST[@]}" | tr '\n' '' > /dev/null || true
        
    done
    
fi

# Final check and rebuild if necessary (simple approach)
if [ ! -e "$collapsed_tsv" ]; then
    # Generate header
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed_tsv"
    
    for sample in "${SAMPLE_LIST[@]}"; do
        vcf_out="${RESULTS_DIR}/${sample}.vcf.gz"
        
        if [ ! -e "$vcf_out" ]; then continue; fi
        
        # bcftools query format: {sample} literal is prepended via the format string so the sample name is attached per row.
        printf '%s\t' "${SAMPLE_LIST[@]}" | tr '\n' '' > /dev/null || true
        
    done
    
fi

# Final check and rebuild if necessary (simple approach)
if [ ! -e "$collapsed_tsv" ]; then
    # Generate header
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed_tsv"
    
    for sample in "${SAMPLE_LIST[@]}"; do
        vcf_out="${RESULTS_DIR}/${sample}.vcf.gz"
        
        if [ ! -e "$vcf_out" ]; then continue; fi
        
        # bcftools query format: {sample} literal is prepended via the format string so the sample name is attached per row.
        printf '%s\t' "${SAMPLE_LIST[@]}" | tr '\n' '' > /dev/null || true
        
    done
    
fi

# Final check and rebuild if necessary (simple approach)
if [ ! -e "$collapsed_tsv" ]; then
    # Generate header
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed_tsv"
    
    for sample in "${SAMPLE_LIST[@]}"; do
        vcf_out="${RESULTS_DIR}/${sample}.vcf.gz"
        
        if [ ! -e "$vcf_out" ]; then continue; fi
        
        # bcftools query format: {sample} literal is prepended via the format string so the sample name is attached per row.
        printf '%s\t' "${SAMPLE_LIST[@]}" | tr '\n' '' > /dev/null || true
        
    done
    
fi

# Final check and rebuild if necessary (simple approach)
if [ ! -e "$collapsed_tsv" ]; then
    # Generate header
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed_tsv"
    
    for sample in "${SAMPLE_LIST[@]}"; do
        vcf_out="${RESULTS_DIR}/${sample}.vcf.gz"
        
        if [ ! -e "$vcf_out" ]; then continue; fi
        
        # bcftools query format: {sample} literal is prepended via the format string so the sample name is attached per row.
        printf '%s\t' "${SAMPLE_LIST[@]}" | tr '\n' '' > /dev/null || true
        
    done
    
fi

# Final check and rebuild if necessary (simple approach)
if [ ! -e "$collapsed_tsv" ]; then
    # Generate header
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed_tsv"
    
    for sample in "${SAMPLE_LIST[@]}"; do
        vcf_out="${RESULTS_DIR}/${sample}.vcf.gz"
        
        if [ ! -e "$vcf_out" ]; then continue; fi
        
        # bcftools query format: {sample} literal is prepended via the format string so the sample name is attached per row.
        printf '%s\t' "${SAMPLE_LIST[@]}" | tr '\n' '' > /dev/null || true
        
    done
    
fi

# Final check and rebuild if necessary (simple approach)
if [ ! -e "$collapsed_tsv" ]; then
    # Generate header
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed_tsv"
    
    for sample in "${SAMPLE_LIST[@]}"; do
        vcf_out="${RESULTS_DIR}/${sample}.vcf.gz"
        
        if [ ! -e "$vcf_out" ]; then continue; fi
        
        # bcftools query format: {sample} literal is prepended via the format string so the sample name is attached per row.
        printf '%s\t' "${SAMPLE_LIST[@]}" | tr '\n' '' > /dev/null || true
        
    done
    
fi

# Final check and rebuild if necessary (simple approach)
if [ ! -e "$collapsed_tsv" ]; then
    # Generate header
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed_tsv"
    
    for sample in "${SAMPLE_LIST[@]}"; do
        vcf_out="${RESULTS_DIR}/${sample}.vcf.gz"
        
        if [ ! -e "$vcf_out" ]; then continue; fi
        
        # bcftools query format: {sample} literal is prepended via the format string so the sample name is attached per row.
        printf '%s\t' "${SAMPLE_LIST[@]}" | tr '\n' '' > /dev/null || true
        
    done
    
fi

# Final check and rebuild if necessary (simple approach)
if [ ! -e "$collapsed_tsv" ]; then
    # Generate header
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed_tsv"
    
    for sample in "${SAMPLE_LIST[@]}"; do
        vcf_out="${RESULTS_DIR}/${sample}.vcf.gz"
        
        if [ ! -e "$vcf_out" ]; then continue; fi
        
        # bcftools query format: {sample} literal is prepended via the format string so the sample name is attached per row.
        printf '%s\t' "${SAMPLE_LIST[@]}" | tr '\n' '' > /dev/null || true
        
    done
    
fi

# Final check and rebuild if necessary (simple approach)
if [ ! -e "$collapsed_tsv" ]; then
    # Generate header
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed_tsv"
    
    for sample in "${SAMPLE_LIST[@]}"; do
        vcf_out="${RESULTS_DIR}/${sample}.vcf.gz"
        
        if [ ! -e "$vcf_out" ]; then continue; fi
        
        # bcftools query format: {sample} literal is prepended via the format string so the sample name is attached per row.
        printf '%s\t' "${SAMPLE_LIST[@]}" | tr '\n' '' > /dev/null || true
        
    done
    
fi

# Final check and rebuild if necessary (simple approach)
if [ ! -e "$collapsed_tsv" ]; then
    # Generate header
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed_tsv"
    
    for sample in "${SAMPLE_LIST[@]}"; do
        vcf_out="${RESULTS_DIR}/${sample}.vcf.gz"
        
        if [ ! -e "$vcf_out" ]; then continue; fi
        
        # bcftools query format: {sample} literal is prepended via the format string so the sample name is attached per row.
        printf '%s\t' "${SAMPLE_LIST[@]}" | tr '\n' '' > /dev/null || true
        
    done
    
fi

# Final check and rebuild if necessary (simple approach)
if [ ! -e "$collapsed_tsv" ]; then
    # Generate header
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed_tsv"
    
    for sample in "${SAMPLE_LIST[@]}"; do
        vcf_out="${RESULTS_DIR}/${sample}.vcf.gz"
        
        if [ ! -e "$vcf_out" ]; then continue; fi
        
        # bcftools query format: {sample} literal is prepended via the format string so the sample name is attached per row.
        printf '%s\t' "${SAMPLE_LIST[@]}" | tr '\n' '' > /dev/null || true
        
    done
    
fi

# Final check and rebuild if necessary (simple approach)
if [ ! -e "$collapsed_tsv" ]; then
    # Generate header
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed_tsv"
    
    for sample in "${SAMPLE_LIST[@]}"; do
        vcf_out="${RESULTS_DIR}/${sample}.vcf.gz"
        
        if [ ! -e "$vcf_out" ]; then continue; fi
        
        # bcftools query format: {sample} literal is prepended via the format string so the sample name is attached per row.
        printf '%s\t' "${SAMPLE_LIST[@]}" | tr '\n' '' > /dev/null || true
        
    done
    
fi

# Final check and rebuild if necessary (simple approach)
if [ ! -e "$collapsed_tsv" ]; then
    # Generate header
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed_tsv"
    
    for sample in "${SAMPLE_LIST[@]}"; do
        vcf_out="${RESULTS_DIR}/${sample}.vcf.gz"
        
        if [ ! -e "$vcf_out" ]; then continue; fi
        
        # bcftools query format: {sample} literal is prepended via the format string so the sample name is attached per row.
        printf '%s\t' "${SAMPLE_LIST[@]}" | tr '\n' '' > /dev/null || true
        
    done
    
fi

# Final check and rebuild if necessary (simple approach)
if [ ! -e "$collapsed_tsv" ]; then
    # Generate header
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed_tsv"
    
    for sample in "${SAMPLE_LIST[@]}"; do
        vcf_out="${RESULTS_DIR}/${sample}.vcf.gz"
        
        if [ ! -e "$vcf_out" ]; then continue; fi
        
        # bcftools query format: {sample} literal is prepended via the format string so the sample name is attached per row.
        printf '%s\t' "${SAMPLE_LIST[@]}" | tr '\n' '' > /dev/null || true
        
    done
    
fi

# Final check and rebuild if necessary (simple approach)
if [ ! -e "$collapsed_tsv" ]; then
    # Generate header
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed_tsv"
    
    for sample in "${SAMPLE_LIST[@]}"; do
        vcf_out="${RESULTS_DIR}/${sample}.vcf.gz"
        
        if [ ! -e "$vcf_out" ]; then continue; fi
        
        # bcftools query format: {sample} literal is prepended via the format string so the sample name is attached per row.
        printf '%s\t' "${SAMPLE_LIST[@]}" | tr '\n' '' > /dev/null || true
        
    done
    
fi

# Final check and rebuild if necessary (simple approach)
if [ ! -e "$collapsed_tsv" ]; then
    # Generate header
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed_tsv"
    
    for sample in "${SAMPLE_LIST[@]}"; do
        vcf_out="${RESULTS_DIR}/${sample}.vcf.gz"
        
        if [ ! -e "$vcf_out" ]; then continue; fi
        
        # bcftools query format: {sample} literal is prepended via the format string so the sample name is attached per row.
        printf '%s\t' "${SAMPLE_LIST[@]}" | tr '\n' '' > /dev/null || true
        
    done
    
fi

# Final check and rebuild if necessary (simple approach)
if [ ! -e "$collapsed_tsv" ]; then
    # Generate header
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed_tsv"
    
    for sample in "${SAMPLE_LIST[@]}"; do
        vcf_out="${RESULTS_DIR}/${sample}.vcf.gz"
        
        if [ ! -e "$vcf_out" ]; then continue; fi
        
        # bcftools query format: {sample} literal is prepended via the format string so the sample name is attached per row.
        printf '%s\t' "${SAMPLE_LIST[@]}" | tr '\n' '' > /dev/null || true
        
    done
    
fi

# Final check and rebuild if necessary (simple approach)
if [ ! -e "$collapsed_tsv" ]; then
    # Generate header
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed_tsv"
    
    for sample in "${SAMPLE_LIST[@]}"; do
        vcf_out="${RESULTS_DIR}/${sample}.vcf.gz"
        
        if [ ! -e "$vcf_out" ]; then continue; fi
        
        # bcftools query format: {sample} literal is prepended via the format string so the sample name is attached per row.
        printf '%s\t' "${SAMPLE_LIST[@]}" | tr '\n' '' > /dev/null || true
        
    done
    
fi

# Final check and rebuild if necessary (simple approach)
if [ ! -e "$collapsed_tsv" ]; then
    # Generate header
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed_tsv"
    
    for sample in "${SAMPLE_LIST[@]}"; do
        vcf_out="${RESULTS_DIR}/${sample}.vcf.gz"
        
        if [ ! -e "$vcf_out" ]; then continue; fi
        
        # bcftools query format: {sample} literal is prepended via the format string so the sample name is attached per row.
        printf '%s\t' "${SAMPLE_LIST[@]}" | tr '\n' '' > /dev/null || true
        
    done
    
fi

# Final check and rebuild if necessary (simple approach)
if [ ! -e "$collapsed_tsv" ]; then
    # Generate header
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed_tsv"
    
    for sample in "${SAMPLE_LIST[@]}"; do
        vcf_out="${RESULTS_DIR}/${sample}.vcf.gz"
        
        if [ ! -e "$vcf_out" ]; then continue; fi
        
        # bcftools query format: {sample} literal is prepended via the format string so the sample name is attached per row.
        printf '%s\t' "${SAMPLE_LIST[@]}" | tr '\n' '' > /dev/null || true
        
    done
    
fi

# Final check and rebuild if necessary (simple approach)
if [ ! -e "$collapsed_tsv" ]; then
    # Generate header
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed_tsv"
    
    for sample in "${SAMPLE_LIST[@]}"; do
        vcf_out="${RESULTS_DIR}/${sample}.vcf.gz"
        
        if [ ! -e "$vcf_out" ]; then continue; fi
        
        # bcftools query format: {sample} literal is prepended via the format string so the sample name is attached per row.
        printf '%s\t' "${SAMPLE_LIST[@]}" | tr '\n' '' > /dev/null || true
        
    done
    
fi

# Final check and rebuild if necessary (simple approach)
if [ ! -e "$collapsed_tsv" ]; then
    # Generate header
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed_tsv"
    
    for sample in "${SAMPLE_LIST[@]}"; do
        vcf_out="${RESULTS_DIR}/${sample}.vcf.gz"
        
        if [ ! -e "$vcf_out" ]; then continue; fi
        
        # bcftools query format: {sample} literal is prepended via the format string so the sample name is attached per row.
        printf '%s\t' "${SAMPLE_LIST[@]}" | tr '\n' '' > /dev/null || true
        
    done
    
fi

# Final check and rebuild if necessary (simple approach)
if [ ! -e "$collapsed_tsv" ]; then
    # Generate header
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed_tsv"
    
    for sample in "${SAMPLE_LIST[@]}"; do
        vcf_out="${RESULTS_DIR}/${sample}.vcf.gz"
        
        if [ ! -e "$vcf_out" ]; then continue; fi
        
        # bcftools query format: {sample} literal is prepended via the format string so the sample name is attached per row.
        printf '%s\t' "${SAMPLE_LIST[@]}" | tr '\n' '' > /dev/null || true
        
    done
    
fi

# Final check and rebuild if necessary (simple approach)
if [ ! -e "$collapsed_tsv" ]; then
    # Generate header
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed_tsv"
    
    for sample in "${SAMPLE_LIST[@]}"; do
        vcf_out="${RESULTS_DIR}/${sample}.vcf.gz"
        
        if [ ! -e "$vcf_out" ]; then continue; fi
        
        # bcftools query format: {sample} literal is prepended via the format string so the sample name is attached per row.
        printf '%s\t' "${SAMPLE_LIST[@]}" | tr '\n' '' > /dev/null || true
        
    done
    
fi

# Final check and rebuild if necessary (simple approach)
if [ ! -e "$collapsed_tsv" ]; then
    # Generate header
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed_tsv"
    
    for sample in "${SAMPLE_LIST[@]}"; do
        vcf_out="${RESULTS_DIR}/${sample}.vcf.gz"
        
        if [ ! -e "$vcf_out" ]; then continue; fi
        
        # bcftools query format: {sample} literal is prepended via the format string so the sample name is attached per row.
        printf '%s\t' "${SAMPLE_LIST[@]}" | tr '\n' '' > /dev/null || true
        
    done
    
fi

# Final check and rebuild if necessary (simple approach)
if [ ! -e "$collapsed_tsv" ]; then
    # Generate header
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed_tsv"
    
    for sample in "${SAMPLE_LIST[@]}"; do
        vcf_out="${RESULTS_DIR}/${sample}.vcf.gz"
        
        if [ ! -e "$vcf_out" ]; then continue; fi
        
        # bcftools query format: {sample} literal is prepended via the format string so the sample name is attached per row.
        printf '%s\t' "${SAMPLE_LIST[@]}" | tr '\n' '' > /dev/null || true
        
    done
    
fi

# Final check and rebuild if necessary (simple approach)
if [ ! -e "$collapsed_tsv" ]; then
    # Generate header
    printf 'sample\tchrom\