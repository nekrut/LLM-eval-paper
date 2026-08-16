#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
REF="data/ref/chrM.fa"
RAW_DIR="data/raw"
RESULTS_DIR="results"

mkdir -p "$RESULTS_DIR"

# --- 2. Reference Indexing (once) ---
if [ ! -f "${REF}.faidx" ] || [ ! -f "${REF}.amb" ]; then
    samtools faidx "$REF"
    bwa index "$REF"
fi

# --- Helper to check idempotency for per-sample steps ---
check_vcf_ready() {
    local sample="$1"
    if [ -f "results/${sample}.vcf.gz.tbi" ]; then
        return 0 # Ready
    fi
}

run_per_sample() {
    local sample="$1"
    
    # Check idempotency: skip if VCF is already indexed and newer than inputs (or simply exists)
    # Since we need to ensure no re-running, checking existence of the final index file is sufficient for a clean run.
    if check_vcf_ready "$sample"; then
        return 0
    fi

    local fq1="${RAW_DIR}/${sample}_1.fq.gz"
    local fq2="${RAW_DIR}/${sample}_2.fq.gz"
    
    # Ensure input files exist (basic sanity, though dataset assumes they do)
    if [ ! -f "$fq1" ] || [ ! -f "$fq2" ]; then
        echo "Error: Missing input FASTQ for sample $sample" >&2
        exit 1
    fi

    # Step 3. Alignment with BWA mem (using literal backslash-t in RG)
    bwa mem -t ${THREADS} \
        -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
        "$REF" "$fq1" "$fq2" | samtools sort -@ ${THREADS} -o "results/${sample}.bam"

    # Step 5. BAM Indexing
    samtools index -@ ${THREADS} "results/${sample}.bam"

    # Step 6. Variant calling with lofreq call-parallel (uncompressed VCF)
    lofreq call-parallel --pp-threads ${THREADS} \
        -f "$REF" \
        -o "results/${sample}.vcf" \
        "results/${sample}.bam"

    # Step 7. Compress and Index VCF (remove uncompressed intermediate)
    bgzip -c "results/${sample}.vcf" > "results/${sample}.vcf.gz"
    rm -f "results/${sample}.vcf"
    tabix -p vcf "results/${sample}.vcf.gz"

}

# --- 3 & 4. Per-sample processing loop ---
for sample in "${SAMPLES[@]}"; do
    run_per_sample "$sample" || exit 1
done

# --- 8. Collapse step ---
TSV_FILE="collapsed.tsv"

if [ -f "$TSV_FILE" ]; then
    # Check if any input VCF is newer than the TSV to decide whether to rebuild
    latest_vcf_time=$(find "results"/"${SAMPLES[@]}"/*.vcf.gz -printf '%T@ %p\n' | sort -rn | head -1)
    
    tsv_mtime=$(stat -c %Y "$TSV_FILE" 2>/dev/null || echo 0)
    latest_vcf_time=${latest_vcf_time:-0}

    if [ "${tsv_mtime}" != "0" ] && (( $(echo "$tsv_mtime > $latest_vcf_time" | bc -l) )); then
        # Rebuild needed (or just always rebuild to be safe, but prompt implies conditional logic based on timestamps or existence of newer inputs)
        : 
    fi
    
fi

# Build collapsed.tsv: Header + all samples concatenated
{
    printf 'sample\tchrom\tpos\tref\talt\taf\n'
    
    for sample in "${SAMPLES[@]}"; do
        if [ -n "$sample" ]; then
            # bcftools query format includes %CHROM, so we don't need to prepend manually inside the loop logic other than relying on the output structure.
            # However, the prompt says: "bcftools query ... ({sample} literal is prepended via the format string)". 
            # Actually, standard bcftools query does NOT automatically prefix sample names unless specified in FORMAT or if using specific flags like -s (which isn't available here).
            # The instruction says: "{sample}\t%CHROM\t..." where {sample} is a literal placeholder. In bash substitution ${sample}, this becomes the string "M117-bl".
            bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" \
                "results/${sample}.vcf.gz" >> "$TSV_FILE"
        fi
    done
}