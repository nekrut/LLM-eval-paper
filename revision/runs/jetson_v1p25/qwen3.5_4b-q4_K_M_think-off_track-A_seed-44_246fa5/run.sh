#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
REF="data/ref/chrM.fa"
RAW_DIR="data/raw"
RES_DIR="results"

mkdir -p "$RES_DIR" data/ref 2>/dev/null || true

# Check if all inputs exist before proceeding (idempotency guard)
for s in "${SAMPLES[@]}"; do
    f1="$RAW_DIR/${s}_1.fq.gz"
    f2="$RAW_DIR/${s}_2.fq.gz"
    [ -f "$f1" ] || exit 0
    [ -f "$f2" ] || exit 0
done

# Reference indexing (once)
if ! [ -e "${REF}.fai" ]; then
    samtools faidx "$REF" --non-recursive
fi
if ! bwa index "$REF"; then
    echo "Error: BWA indexing failed." >&2
    exit 1
fi

# Per-sample processing loop
for s in "${SAMPLES[@]}"; do
    f1="$RAW_DIR/${s}_1.fq.gz"
    f2="$RAW_DIR/${s}_2.fq.gz"
    
    # Check if final VCF index exists (idempotency guard)
    vcf_idx="${RES_DIR}/${s}.vcf.gz.tbi"
    [ -e "$vcf_idx" ] && continue
    
    # Step 3: Alignment with BWA mem using literal backslash-t in RG string
    bwa_mem_cmd="bwa mem -t $THREADS \"$REF\" -R \"@RG\\tID:${s}\\tSM:${s}\\tLB:${s}\\tPL:ILLUMINA\""
    
    # Step 4 & 5: Sort and index BAM (pipe directly to avoid temp files)
    eval "$bwa_mem_cmd" | samtools sort -@ $THREADS -o "${RES_DIR}/${s}.bam" || exit 1
    
    if ! [ -e "${RES_DIR}/${s}.bam.bai" ]; then
        samtools index -@ $THREADS "${RES_DIR}/${s}.bam" || exit 1
    fi

done

# Step 6 & 7: Variant calling, compression, and indexing (per sample)
for s in "${SAMPLES[@]}"; do
    vcf="${RES_DIR}/${s}.vcf.gz.tbi"
    
    # Check if final VCF index exists (idempotency guard for this step too)
    [ -e "$vcf" ] && continue
    
    bam="${RES_DIR}/${s}.bam.bai"
    
    lofreq call-parallel --pp-threads $THREADS -f "$REF" -o "${RES_DIR}/${s}.vcf" "${bam}" || exit 1
    
    # Compress and index VCF (bgzip is required per plan)
    bgzip -c "${RES_DIR}/${s}.vcf" > "${RES_DIR}/${s}.vcf.gz" && mv "${RES_DIR}/${s}.vcf.gz" "${RES_DIR}/${s}.vcf.tmp" || exit 1
    
    # Remove uncompressed intermediate if it exists (lofreq might leave a .vcf)
    rm -f "${RES_DIR}/${s}.vcf"
    
    tabix -p vcf "${RES_DIR}/${s}.vcf.gz" > /dev/null || exit 1

done

# Step 8: Collapse step -> results/collapsed.tsv
tsv="${RES_DIR}/collapsed.tsv"
header="sample\tchrom\tpos\tref\talt\taf"

if ! [ -e "$tsv" ]; then
    # Rebuild only if any input VCF is newer than the TSV (idempotency)
    latest_vcf=""
    for s in "${SAMPLES[@]}"; do
        vcf="${RES_DIR}/${s}.vcf.gz.tbi"
        [ -e "$vcf" ] || continue
        
        if ! [ -e "$tsv" ]; then
            # First run: just build it
            :
        else
            # Check timestamps to decide if rebuild is needed (simple check)
            vcf_time=$(stat -c %Y "$vcf") 2>/dev/null || true
            tsv_time=$(stat -c %Y "$tsv" 2>/dev/null || echo "0")
            
            max_vtf=$vcf_time
            for s in "${SAMPLES[@]}"; do
                vcf="${RES_DIR}/${s}.vcf.gz.tbi"
                [ ! -e "$vcf" ] && continue
                t=$(stat -c %Y "$vcf" 2>/dev/null || echo "0")
                if ((t > max_vtf)); then
                    max_vtf=$t
                fi
            done
            
            # Rebuild only if the latest VCF is newer than TSV
            if [ $max_vtf -gt $tsv_time ]; then
                :
            else
                continue
            fi
        fi
        
        query_cmd="bcftools query -f '{sample}\t%%CHROM\t%%POS\t%%REF\t%%ALT\t%%INFO/AF\n' \"${RES_DIR}/${s}.vcf.gz\""
        
        # Capture output to temp file for concatenation (avoids piping issues)
        tmp_out=$(mktemp) || exit 1
        
        eval "$query_cmd" > "$tmp_out" || { rm -f "$tmp_out"; continue; }

done

# Ensure header exists and append data from all samples in order
if [ ! -e "$tsv" ]; then
    echo "$header" > "$tsv"
fi

for s in "${SAMPLES[@]}"; do
    vcf="${RES_DIR}/${s}.vcf.gz.tbi"
    if [ -e "$vcf" ]; then
        query_cmd="bcftools query -f '{sample}\t%%CHROM\t%%POS\t%%REF\t%%ALT\t%%INFO/AF\n' \"${RES_DIR}/${s}.vcf.gz\""
        
        tmp_out=$(mktemp) || exit 1
        
        eval "$query_cmd" > "$tmp_out" || { rm -f "$tmp_out"; continue; }

        # Append to TSV (skip header if it exists, but we already wrote one or will write now)
        tail -n +2 "$tsv" | grep -v "^${s}	" >> "${RES_DIR}/collapsed.tsv.tmp" || true
        
        cat "$tmp_out" >> "${RES_DIR}/collapsed.tsv.tmp" 2>/dev/null || rm -f "$tmp_out"; continue

done