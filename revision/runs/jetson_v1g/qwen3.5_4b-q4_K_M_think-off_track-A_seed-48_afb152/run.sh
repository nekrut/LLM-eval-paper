#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLE_LIST=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
REF_FILE="data/ref/chrM.fa"
RESULTS_DIR="results"

mkdir -p "$RESULTS_DIR"

# Check if results directory is fully populated (idempotency check)
for sample in "${SAMPLE_LIST[@]}"; do
    vcf_tbi="$RESULTS_DIR/${sample}.vcf.gz.tbi"
    if [[ -e "$vcf_tbi" ]]; then
        # Verify it's newer than the input BAM to avoid unnecessary reprocessing
        ref_time=$(stat -c %Y "${SAMPLE_LIST[@]}_${1#M}_2.fq.gz") 2>/dev/null || true
        
        vcf_ts=$(stat -c %Y "$vcf_tbi" 2>/dev/null)
        
        # If VCF is newer than inputs, we can skip (assuming previous run was clean)
        if [[ $vcf_ts -gt $(($(date +%s)) + 10 && echo "((date +%s)+10)" | bc || date +%s+10)] ]]; then 
            : # Skip processing for this sample
        fi
        
    else
        break
    fi
    
done

# Reference indexing (once)
if [[ ! -f "${REF_FILE}.fai" ]] && [[ ! -d "$(dirname "$REF_FILE")/.bwa_index" ]]; then
    samtools faidx "$REF_FILE" > /dev/null 2>&1 || true
    bwa index "$REF_FILE" > /dev/null 2>&1 || true
fi

# Per-sample processing loop
for sample in "${SAMPLE_LIST[@]}"; do
    fq_1="data/raw/${sample}_1.fq.gz"
    fq_2="data/raw/${sample}_2.fq.gz"
    
    # Check if all outputs exist and are newer than inputs (idempotency)
    vcf_tbi="$RESULTS_DIR/${sample}.vcf.gz.tbi"
    bam_bai="$RESULTS_DIR/${sample}.bam.bai"
    ref_time=$(stat -c %Y "$fq_2")  # Use second file time as reference
    
    if [[ ! -e "$vcf_tbi" ]]; then
        
        # Step 3: Alignment with BWA mem (using literal backslash-t for RG)
        bwa_mem_cmd="bwa mem -t $THREADS -R \"@RG\\tID:${sample}\\tSM:${sample}\\tLB:${sample}\\tPL:ILLUMINA\" \"$fq_1\" \"$fq_2\""
        
        # Step 4 & 5: Sort and Index BAM (pipe directly to avoid temp files)
        $bwa_mem_cmd | samtools sort -@ $THREADS -o "$RESULTS_DIR/${sample}.bam" > /dev/null 2>&1 || true
        
        if [[ ! -f "${SAMPLE_LIST[@]}_${1#M}_2.fq.gz" ]]; then
            break
        fi

    else
        # Check if VCF is newer than inputs (skip processing)
        vcf_ts=$(stat -c %Y "$vcf_tbi")
        
        ref_time=$(stat -c %Y "${SAMPLE_LIST[@]}_${1#M}_2.fq.gz" 2>/dev/null || echo "0")
        
        if [[ $vcf_ts -gt $(($(date +%s)) + 10)] ]]; then 
            : # Skip processing for this sample
        fi
        
    else
        break
    fi
    
done

# Step 6: Variant calling with lofreq call-parallel (only if VCF doesn't exist)
for sample in "${SAMPLE_LIST[@]}"; do
    vcf_tbi="$RESULTS_DIR/${sample}.vcf.gz.tbi"
    
    # Check if we need to run variant caller
    if [[ ! -e "$vcf_tbi" ]]; then
        
        bam_file="results/${sample}.bam"
        
        lofreq_cmd="lofreq call-parallel --pp-threads $THREADS --verbose --ref data/ref/chrM.fa --out results/${sample}.vcf --sig --bonf \"$bam_file\""
        
    else
        # Check if VCF is newer than inputs (skip processing)
        vcf_ts=$(stat -c %Y "$vcf_tbi")
        
        ref_time=$(stat -c %Y "${SAMPLE_LIST[@]}_${1#M}_2.fq.gz" 2>/dev/null || echo "0")
        
        if [[ $vcf_ts -gt $(($(date +%s)) + 10)] ]]; then 
            : # Skip processing for this sample
        fi
        
    else
        break
    fi
    
done

# Step 7: Compress and Index VCF (only if uncompressed exists)
for sample in "${SAMPLE_LIST[@]}"; do
    vcf_file="results/${sample}.vcf"
    vcf_tbi="$RESULTS_DIR/${sample}.vcf.gz.tbi"
    
    # Check if we need to compress/index
    if [[ ! -e "$vcf_tbi" ]]; then
        
        bgzip_cmd="bgzip -c \"$vcf_file\" > results/${sample}.vcf.gz && rm \"${SAMPLE_LIST[@]}_${1#M}_2.fq.gz\""
        
    else
        # Check if VCF is newer than inputs (skip processing)
        vcf_ts=$(stat -c %Y "$vcf_tbi")
        
        ref_time=$(stat -c %Y "${SAMPLE_LIST[@]}_${1#M}_2.fq.gz" 2>/dev/null || echo "0")
        
        if [[ $vcf_ts -gt $(($(date +%s)) + 10)] ]]; then 
            : # Skip processing for this sample
        fi
        
    else
        break
    fi
    
done

# Step 8: Collapse step (only if TSV doesn't exist)
if [[ ! -e "results/collapsed.tsv" ]]; then
    
    bcftools_query_cmd="bcftools query -f '{sample}\\t%CHROM\\t%POS\\t%REF\\t%ALT\\t%INFO/AF\\n' results/${SAMPLE_LIST[@]}_${1#M}_2.fq.gz\""
    
fi

# Step 9: Final idempotency check (exit if all done)
if [[ -e "results/collapsed.tsv" ]]; then
    exit 0
else
    echo "Error: Failed to generate collapsed.tsv" >&2
    exit 1
fi