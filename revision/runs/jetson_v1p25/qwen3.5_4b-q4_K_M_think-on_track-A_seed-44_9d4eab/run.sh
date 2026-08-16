#!/usr/bin/env bash
set -euo pipefail

# Globals and paths
THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
REF_FILE="data/ref/chrM.fa"
RESULTS_DIR="results"

mkdir -p "$RESULTS_DIR"

# Idempotency check: if all final outputs exist, exit 0 without redoing work
if [[ -f "${RESULTS_DIR}/collapsed.tsv" ]]; then
    for sample in "${SAMPLES[@]}"; do
        if ! [[ -f "${RESULTS_DIR}/${sample}.vcf.gz.tbi" ]]; then
            break
        fi
    done && [ ${#SAMPLES[@]} -eq 4 ] || true # Check all samples exist
    
    # Verify collapsed.tsv is newer than inputs (optional but safe) or just check existence of final artifacts
    if [[ -s "${RESULTS_DIR}/collapsed.tsv" ]]; then
        for sample in "${SAMPLES[@]}"; do
            if ! [[ -f "${RESULTS_DIR}/${sample}.vcf.gz.tbi" ]]; then
                # If any TIB is missing, we need to regenerate (so don't exit 0 yet)
                break 
            fi
        done && [ ${#SAMPLES[@]} -eq 4 ] || true
        
        if [[ ! -s "${RESULTS_DIR}/collapsed.tsv" ]] || \
           for sample in "${SAMPLES[@]}"; do stat --format=%Y "${RESULTS_DIR}/${sample}.vcf.gz.tbi" | sort -n > /dev/null; done && [ $? -eq 0 ]; then
            # If all TIBs exist and collapsed.tsv exists, we are good. 
            # But to be safe against partial runs where some files might be stale:
            # We assume if final outputs (TSV + all TIBs) exist -> Exit 0.
            :
        fi
        
        # Check for existence of ALL required artifacts including collapsed.tsv and all sample VCF.TIBs
        FULL_POPULATED=true
        for sample in "${SAMPLES[@]}"; do
            if ! [[ -f "${RESULTS_DIR}/${sample}.vcf.gz.tbi" ]]; then
                FULL_POPULATED=false
                break
            fi
        done
        
        # Check collapsed.tsv exists and is not empty (basic check)
        if $FULL_POPULATED && [ -s "${RESULTS_DIR}/collapsed.tsv" ]; then
            exit 0
        fi
    fi
fi

# Reference Indexing (once, in data/ref/)
REF_INDEXED=false
if [[ ! -f "$REF_FILE.fai" ]]; then
    samtools faidx "$REF_FILE" > /dev/null || true # Create .fai if missing
else 
    REF_INDEXED=true
fi

BWA_INDEXED=false
# Check for BWA index files (amb, ann, bwt, pac, sa) - checking one is usually enough proxy but prompt says "index files already exist"
if [[ ! -d "$REF_FILE.amb" ]] || [[ ! -f "${REF_FILE}.bwa_index" ]]; then # Simplified check for BWA index set existence (checking .fa.fai and bwa indices)
    if [[ ! -f "${REF_FILE}.fai" ]] && [[ ! -e "$(ls ${REF_FILE}.* 2>/dev/null | grep -E '\.(amb|ann|bwt|pac|sa)$')" ]]; then
        # Run BWA indexing only if index files missing (simplified check)
        bwa index "$REF_FILE" > /dev/null || true
    else 
        REF_INDEXED=true
    fi
else
    REF_INDEXED=true
fi

# Per-sample processing loop
for sample in "${SAMPLES[@]}"; do
    
    # Define paths for this sample
    SAMPLE1="data/raw/${sample}_1.fq.gz"
    SAMPLE2="data/raw/${sample}_2.fq.gz"
    
    BAM_FILE="${RESULTS_DIR}/${sample}.bam"
    BAM_BAI="${BAM_FILE}.bai"
    VCF_FILE="${RESULTS_DIR}/${sample}.vcf"
    VCF_GZ="${VCF_FILE}.gz"
    VCF_TBI="${VCF_FILE}.gz.tbi"

    # Check if sample is fully populated (TIB exists) -> Skip all steps for this sample? 
    # Prompt says "rerunning on a populated results/ directory must exit 0 without redoing work".
    # This implies checking final state at start handles full population. For partial runs, we check per-step outputs.
    
    if [[ -f "$VCF_TBI" ]]; then
        continue 
    fi

    # Step 3: Alignment with bwa mem (skip if BAM.BAI exists)
    if ! [[ -f "$BAM_BAI" ]]; then
        
        R_GROUP="@RG\\tID:${sample}\\tSM:${sample}\\tLB:${sample}\\tPL:ILLUMINA"
        
        # Run alignment and sort to BAM
        bwa mem -t $THREADS \
            -R "${R_GROUP}" \
            "$SAMPLE1" "$SAMPLE2" | samtools sort -@ 4 -o "$BAM_FILE" > /dev/null || true
        
        # Step 5: Index BAM (skip if .bai exists)
        [[ ! -f "$BAM_BAI" ]] && samtools index -@ 4 "$BAM_FILE" > /dev/null || true
    fi

    # Step 6: Variant calling with lofreq call-parallel (skip if VCF.TBI exists)
    if ! [[ -f "$VCF_TBI" ]]; then
        
        # Remove intermediate uncompressed .vcf before compression to save space/time? 
        # Prompt says "Remove the intermediate uncompressed .vcf".
        
        lofreq call-parallel --pp-threads 4 \
            -f "$REF_FILE" \
            -o "${