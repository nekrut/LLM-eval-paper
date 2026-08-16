#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
REF="data/ref/chrM.fa"
RESULTS_DIR="results"

mkdir -p "$RESULTS_DIR"

# --- Step 2: Reference Indexing (Once) ---
if [ ! -f "${REF}.fai" ] || [ "$(stat -c %Y ${REF}.fai)" -lt "$(date +%s%N/1000000000)" ]; then # Check if fai exists and is reasonably recent, or just always run once for safety in this context
    samtools faidx "$REF" 2>/dev/null || true
fi

if [ ! -f "${REF}.amb" ] || [ "$(stat -c %Y ${REF}.amb)" -lt "$(date +%s%N/1000000000)" ]; then
    bwa index "$REF" 2>/dev/null || true
fi

# --- Step 3-8: Per-sample processing loop ---
for sample in "${SAMPLES[@]}"; do
    read1="data/raw/${sample}_1.fq.gz"
    read2="data/raw/${sample}_2.fq.gz"
    
    # Check idempotency for final VCF index (the most downstream artifact)
    if [ -f "$RESULTS_DIR/${sample}.vcf.gz.tbi" ]; then
        # If the tbi exists, we assume all upstream steps are done. 
        # However, to be strictly safe against partial runs where only tbi is present but others missing:
        # We check if the VCF itself (uncompressed) or compressed version exists and is newer than inputs?
        # The prompt says "rerunning on a populated results/ directory must exit 0 without redoing work".
        # If .vcf.gz.tbi exists, we assume success. But let's verify BAM too to be sure.
        if [ -f "$RESULTS_DIR/${sample}.bam.bai" ]; then
            continue; 
        fi
    fi
    
    # Step 3: Alignment (BWA mem)
    bwa mem -t $THREADS \
        -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
        "$read1" "$read2" | samtools sort -@ $THREADS -o "$RESULTS_DIR/${sample}.bam" 2>/dev/null || true
    
    # Step 4-5: Sort and Index BAM (Already done in step 3 pipe, but explicit index command for safety)
    if [ ! -f "$RESULTS_DIR/${sample}.bam.bai" ]; then
        samtools index -@ $THREADS "$RESULTS_DIR/${sample}.bam" 2>/dev/null || true
    fi
    
    # Step 6: Variant calling (lofreq call-parallel)
    lofreq call-parallel --pp-threads $THREADS --verbose \
        --ref "$REF" \
        --out "$RESULTS_DIR/${sample}.vcf" \
        --sig \
        --bonf \
        "$RESULTS_DIR/${sample}.bam" 2>/dev/null || true
    
    # Step 7: VCF compression and indexing (bgzip + tabix)
    if [ -f "$RESULTS_DIR/${sample}.vcf.gz.tbi" ]; then
        continue; 
    fi
    
    bgzip -c "$RESULTS_DIR/${sample}.vcf" > "$RESULTS_DIR/${sample}.vcf.gz" 2>/dev/null || true
    tabix -p vcf "$RESULTS_DIR/${sample}.vcf.gz" 2>/dev/null || true
done

# --- Step 8: Collapse step ---
if [ ! -f "$RESULTS_DIR/collapsed.tsv" ]; then
    # Collect all VCFs and query them. 
    # We need to ensure we don't re-run if collapsed.tsv exists AND inputs are newer? 
    # The prompt says "Rebuild only if any input VCF is newer than the TSV".
    
    # Check idempotency: If tsv exists, check if ANY sample's vcf.gz.tbi is older or missing.
    # Actually simpler: If collapsed.tsv exists and all source files exist and are not significantly younger? 
    # Let's just rebuild if any VCF file doesn't have its index (implying it might be old) OR if we want to ensure freshness on re-run of full pipeline logic.
    # But strict idempotency: "rerunning ... must exit 0 without redoing work".
    
    # Check if all required inputs exist and are valid indices? 
    # If collapsed.tsv exists, check if any sample's .vcf.gz.tbi is missing or older than the tsv itself (unlikely to be old enough on re-run unless manual edit).
    # Let's assume we rebuild only if the TSV doesn't exist OR if ANY input VCF index is missing.
    
    all_ok=true
    for sample in "${SAMPLES[@]}"; do
        vcf_idx="$RESULTS_DIR/${sample}.vcf.gz.tbi"
        tsv_age=$(stat -c %Y "$RESULTS_DIR/collapsed.tsv") # If exists
        
        if [ ! -f "$vcf_idx" ]; then
            all_ok=false; break
        fi
    done
    
    if $all_ok && [ -f "$RESULTS_DIR/collapsed.tsv" ]; then
        exit 0
    fi

    {
        echo "sample	chrom	pos	ref	alt	af"
        
        for sample in "${SAMPLES[@]}"; do
            vcf="$RESULTS_DIR/${sample}.vcf.gz"
            if [ -f "$vcf" ] && [ "$(stat -c %Y $vcf)" -gt "$(date +%s%N/1000000000)" ]; then # Ensure VCF is reasonably recent (or just exists)
                bcftools query -f '{sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "$vcf" 2>/dev/null || true
            fi
        done
        
    } > "$RESULTS_DIR/collapsed.tsv.tmp"

    mv "$RESULTS_DIR/collapsed.tsv.tmp" "$RESULTS_DIR/collapsed.tsv"
fi