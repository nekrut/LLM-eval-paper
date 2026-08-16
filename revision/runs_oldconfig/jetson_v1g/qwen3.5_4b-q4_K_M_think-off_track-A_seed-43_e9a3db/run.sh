#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
REF="data/ref/chrM.fa"
RESULTS_DIR="results"

mkdir -p "$RESULTS_DIR"

# Check if results directory is fully populated (idempotency check)
for sample in "${SAMPLES[@]}"; do
    vcf_tbi="$RESULTS_DIR/${sample}.vcf.gz.tbi"
    if [[ -e "$vcf_tbi" ]]; then
        # If TBI exists, assume all artifacts are present and up to date for this run context
        break 2
    fi
done

# Reference indexing (once)
if ! samtools faidx --check "$REF" > /dev/null 2>&1; then
    samtools faidx "$REF"
fi

for sample in "${SAMPLES[@]}"; do
    # Check if VCF TBI exists to skip per-sample work
    vcf_tbi="$RESULTS_DIR/${sample}.vcf.gz.tbi"
    if [[ -e "$vcf_tbi" ]]; then
        continue
    fi
    
    read1="data/raw/${sample}_1.fq.gz"
    read2="data/raw/${sample}_2.fq.gz"

    # 3. Alignment with bwa mem (using literal backslash-t for RG)
    bwa_mem_cmd="-t $THREADS -R \"@RG\\tID:${sample}\\tSM:${sample}\\tLB:${sample}\\tPL:ILLUMINA\" ${read1} ${read2}"

    # 4. Sort BAM
    samtools_sort_cmd="samtools sort -@ $THREADS"
    
    # Run alignment and sorting in one pipeline, output to temp file then move if needed (idempotent check on final bam)
    tmp_bam=$(mktemp /tmp/sort_XXXXXX.bam)
    bwa_mem_cmd | ${samtools_sort_cmd} -o "$tmp_bam" > /dev/null 2>&1
    
    # Check if sorted BAM exists and is newer than input to avoid re-sorting unnecessarily, but since we pipe directly, 
    # the existence of .bam.bai implies success. We move temp to final only if it's not already there (which shouldn't happen due to piping)
    mv "$tmp_bam" "${sample}.bam"

    # 5. Index BAM
    samtools index -@ $THREADS "${sample}.bam" > /dev/null 2>&1
    
    # 6. Variant calling with lofreq call-parallel
    lofreq_cmd="lofreq call-parallel --pp-threads $THREADS --verbose --ref ${REF} --out ${RESULTS_DIR}/${sample}.vcf --sig --bonf ${sample}.bam"
    
    if ! eval "$lofreq_cmd"; then
        echo "Error in lofreq calling for sample: $sample" >&2
        exit 1
    fi
    
    # Remove uncompressed VCF to save space and ensure clean state before compression step check
    rm -f "${RESULTS_DIR}/${sample}.vcf"

done

# Collapse step (only if TSV doesn't exist)
if [[ ! -e "$RESULTS_DIR/collapsed.tsv" ]]; then
    tmp_vcf_list=$(mktemp /tmp/vcf_query_XXXXXX.txt)
    
    for sample in "${SAMPLES[@]}"; do
        vcf_file="$RESULTS_DIR/${sample}.vcf.gz"
        # Check if VCF is newer than TSV to avoid re-querying old data unnecessarily (though we rebuild only once per run logic above, 
        # this check ensures idempotency on reruns where inputs haven't changed)
        vcf_mtime=$(stat -c %Y "$vcf_file" 2>/dev/null || stat -f %m "$vcf_file")
        tsv_mtime=$(stat -c %Y "$RESULTS_DIR/collapsed.tsv" 2>/dev/null || echo "0")
        
        if [[ $vcf_mtime -gt $tsv_mtime ]]; then
            bcftools_query_cmd="bcftools query -f '{sample}\\t%CHROM\\t%POS\\t%REF\\t%ALT\\t%INFO/AF\\n' ${vcf_file}"
            
            # Run per sample and append to temp file (overwrite if newer)
            eval "$bcftools_query_cmd" > "${tmp_vcf_list}.temp_${sample}" 2>/dev/null
            
            cat "${tmp_vcf_list}.temp_${sample}" >> "$tmp_vcf_list"
        fi
        
        # Cleanup per-sample temp files to save disk space (optional but good practice)
        rm -f "${tmp_vcf_list}.temp_${sample}"
    done
    
    # Write final TSV with header if it doesn't exist or is older than inputs
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$RESULTS_DIR/collapsed.tsv"
    
    cat "$tmp_vcf_list" >> "$RESULTS_DIR/collapsed.tsv" 2>/dev/null || true
    
    rm -f "$tmp_vcf_list"
fi

exit 0