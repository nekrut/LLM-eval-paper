#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
REF="data/ref/chrM.fa"
RAW_DIR="data/raw/"
RES_DIR="results/"

mkdir -p "$RES_DIR"

# --- 2. Reference Indexing (once) ---
if [ ! -f "${REF}.fai" ] || [ "$(stat -c %Y ${REF}.fai)" -lt "$(date +%s%N/1000000000)" ]; then
    samtools faidx "$REF" 2>/dev/null || true
fi

if ! bwa index "$REF"; then echo "BWA Indexing failed or skipped due to missing files."; exit 1; fi

# --- Per-sample processing loop ---
for sample in "${SAMPLES[@]}"; do
    fq_1="${RAW_DIR}${sample}_1.fq.gz"
    fq_2="${RAW_DIR}${sample}_2.fq.gz"
    
    # Check if all outputs exist to ensure idempotency (skip re-running)
    if [ -f "${RES_DIR}${sample}.bam.bai" ] && \
       [ "$(stat -c %Y ${RES_DIR}${sample}.vcf.gz.tbi)" -gt "$(date +%s%N/1000000000)" ]; then
        continue; # Skip if all outputs are present and VCF is newer than inputs (implied by existence check)
    fi

    RG_LINE="@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA"
    
    bwa mem -t $THREADS "$REF" <(printf '%s\n' "$fq_1") <(printf '%s\n' "$fq_2") 2>/dev/null | \
        samtools sort -@ $THREADS -o "${RES_DIR}${sample}.bam" || exit 1
    
    # Index BAM (skip if exists)
    if [ ! -f "${RES_DIR}${sample}.bam.bai" ]; then
        samtools index -t "$THREADS" "${RES_DIR}${sample}.bam" || exit 1; fi
        
    # Call variants with lofreq call-parallel
    lofreq call-parallel --pp-threads $THREADS \
        --ref "$REF" \
        --bams "${RES_DIR}${sample}.bam" \
        -o "${RES_DIR}${sample}.vcf" 2>/dev/null || exit 1
    
    # Compress and index VCF (skip if exists)
    if [ ! -f "${RES_DIR}${sample}.vcf.gz.tbi" ]; then
        bgzip -c "${RES_DIR}${sample}.vcf" > "${RES_DIR}${sample}.vcf.gz" || exit 1
        tabix -p vcf "${RES_DIR}${sample}.vcf.gz" || exit 1
        
        # Cleanup uncompressed VCF to save space and ensure clean state for next run if needed (though we keep it until collapse)
        rm -f "${RES_DIR}${sample}.vcf"; fi
    
    echo "Processed sample: $sample" >&2; done

# --- 8. Collapse step ---
TSV_FILE="${RES_DIR}collapsed.tsv"

if [ ! -f "$TSV_FILE" ] || \
   [ "$(stat -c %Y ${TSV_FILE})" -lt "$(date +%s%N/1000000000)" ]; then
    
    # Generate header
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$TSV_FILE"
    
    for sample in "${SAMPLES[@]}"; do
        query_out=$(bcftools query -f '{sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' \
            "${RES_DIR}${sample}.vcf.gz") || exit 1
        
        # Append to TSV (skip header)
        printf '%s\n' "$query_out" >> "$TSV_FILE"; fi
    
    echo "Generated collapsed.tsv" >&2; fi

exit 0