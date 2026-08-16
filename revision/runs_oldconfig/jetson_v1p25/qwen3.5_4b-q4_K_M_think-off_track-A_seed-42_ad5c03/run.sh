#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
REF="data/ref/chrM.fa"
RAW_DIR="data/raw"
RES_DIR="results"

mkdir -p "$RES_DIR"

# Reference indexing (once)
if [ ! -f "${REF}.fai" ] || [ "$(stat -c %Y ${REF}.fai 2>/dev/null)" = "0" ]; then
    samtools faidx "$REF" > /dev/null
fi
if [ ! -d "${REF}.amb" ]; then
    bwa index "$REF" > /dev/null
fi

# Per-sample processing loop
for sample in "${SAMPLES[@]}"; do
    f1="${RAW_DIR}/${sample}_1.fq.gz"
    f2="${RAW_DIR}/${sample}_2.fq.gz"
    
    # Check idempotency for VCF output (step 6-7)
    if [ -f "$RES_DIR/${sample}.vcf.gz.tbi" ]; then
        vcf_time=$(stat -c %Y "$RES_DIR/${sample}.vcf.gz")
        bai_time=$(stat -c %Y "${REF}.amb" | head -1 || stat -c %Y "data/ref/chrM.fa.bai" 2>/dev/null) # fallback if fai exists but not amb set yet, though we check dir above. Actually simpler: just compare vcf.gz to input or previous run artifacts if they exist and are newer than inputs? The prompt says "skip if ... already exists".
        # Let's simplify idempotency logic for the whole pipeline per sample based on final VCF index existence vs raw data age, but strictly following plan steps.
        # Plan step 1 says: skip if results/{sample}.vcf.gz.tbi already exists and is newer than its inputs.
        vcf_time=$(stat -c %Y "$RES_DIR/${sample}.vcf.gz")
        
        input_newer=0
        
        # Check if any input file is newer than the current VCF index (which implies it was built from older or same data)
        for f in $f1 $f2; do
            if [ "$(stat -c %Y "$f")" -gt "$vcf_time" ]; then
                input_newer=1
                break
            fi
        done
        
        # Also check against the reference index time to ensure ref is up to date relative to this run? No, just inputs.
        
        if [ $input_newer -eq 0 ] && [ "$(stat -c %Y "${REF}.amb")" != "0" ]; then
            ref_time=$(stat -c %Y "${REF}.amb") # If amb exists (checked above), use it as proxy for 'ref state' or just rely on input age. 
            # Actually, if inputs haven't changed since the last run produced this VCF index, we skip.
        fi
        
        # Refined check: Skip entire per-sample pipeline if vcf.gz.tbi exists and all inputs are older/equal to it?
        # The prompt says "skip if ... newer than its inputs". This implies if current tibi > max(input times), then the work is done (assuming ref didn't change drastically or we trust previous run). 
        # However, usually idempotency means: if output exists and input hasn't changed since last time.
        # Let's implement strict check: If vcf.gz.tbi exists AND all inputs are <= current tibi timestamp? No, that logic is flawed because tibi grows every time we run it even on same data (if not careful). 
        # Correct idempotency for "rerunning ... must exit 0 without redoing work":
        # If the output files exist and the input files have NOT changed since they were last processed? We don't track 'last processed' timestamp.
        # Alternative: Check if inputs are newer than outputs -> run. Else skip. 
        # But what if ref changes? The prompt assumes static dataset mostly, but mentions "skip ... if ... newer".
        # Let's assume the standard pattern: If output exists and max(input times) <= output time (meaning we built it from older data), then skip? No, that means if I run on same data again, outputs are old, inputs are new(er)? No. 
        # Standard logic for idempotent scripts with static input:
        # Run only if any input is newer than the corresponding output index file (or just check existence of final artifact and assume no change needed unless explicitly told to re-index).
        # Given "rerunning on a populated results/ directory must exit 0 without redoing work", we can simply check: 
        # If all inputs are older/equal to the current VCF timestamp? No, that would prevent running if I just touched an input file.
        # Let's use a simpler heuristic often used in these challenges: Check if output exists and is newer than ALL inputs (including ref). If so, skip. 
        # Wait, "newer than its inputs" -> if Output > Inputs, then we are good? Yes. Because that means the work was done recently on this data state.
        
        max_input_time=0
        for f in $f1 $f2; do
            t=$(stat -c %Y "$f")
            [ "$t" -gt "$max_input_time" ] && max_input_time=$t
        done
        
        ref_idx_time=0
        if [ -d "${REF}.amb" ]; then
             # We need a time for the reference index. Since we build it once, let's assume its creation time is fixed or check fai/amb age? 
             # Let's just use the VCF timestamp as the baseline of "work done". If inputs are newer than that work, re-run.
        fi
        
        if [ "$max_input_time" -gt "$(stat -c %Y "${RES_DIR}/${sample}.vcf.gz")" ]; then
            : # Re-run needed (inputs changed)
        else
            continue # Skip per-sample pipeline
        fi

    fi
    
    # Step 3: Alignment
    bwa mem -t $THREADS \
        -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
        "$REF" "$f1" "$f2" | samtools sort -@ $THREADS -o "${RES_DIR}/${sample}.bam"

    # Step 4/5: Index BAM (skip if exists and newer than inputs? Prompt says "BAM indexing", usually done once per sample. 
    # If we skipped alignment, we skip index too. But what if alignment was re-run but not indexed yet?
    # Let's assume if .bam.bai exists and is valid, it might be stale if bam changed. 
    # Simple check: if bai exists and inputs are older than bai -> ok to use. Else rebuild.
    
    if [ -f "${RES_DIR}/${sample}.bam" ]; then
        max_input_time=0
        for f in $f1 $f2; do
            t=$(stat -c %Y "$f")
            [ "$t" -gt "$max_input_time" ] && max_input_time=$t
        done
        
        if [ "$(stat -c %Y "${RES_DIR}/${sample}.bam.bai")" -lt "$max_input_time" ]; then
             samtools index -@ $THREADS "${RES_DIR}/${sample}.bam" > /dev/null
        fi
    else
         # Should not happen due to sort output, but safety check.
         pass=0
    fi

    # Step 6: Variant calling (skip if vcf.gz.tbi exists and inputs <= it)
    if [ -f "${RES_DIR}/${sample}.vcf.gz.tbi" ]; then
        max_input_time=0
        for f in $f1 $f2; do
            t=$(stat -c %Y "$f")
            [ "$t" -gt "$max_input_time" ] && max_input_time=$t
        done
        
        if [ "$(stat -c %Y "${RES_DIR}/${sample}.vcf.gz.tbi")" -lt "$max_input_time" ]; then
             # Re-run call-parallel and compression/indexing
             lofreq call-parallel --pp-threads $THREADS \
                 -f "$REF" \
                 -o "${RES_DIR}/${sample}.vcf" \
                 "${RES_DIR}/${sample}.bam" > /dev/null
            
            bgzip -c "${RES_DIR}/${sample}.vcf" > "${RES_DIR}/${sample}.vcf.gz" && rm "${RES_DIR}/${sample}.vcf"
            
            tabix -p vcf "${RES_DIR}/${sample}.vcf.gz" > /dev/null
        fi
    else
         # Run full pipeline for this sample (alignment, sort, index, call)
         bwa mem -t $THREADS \
             -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
             "$REF" "$f1" "$f2" | samtools sort -@ $THREADS -o "${RES_DIR}/${sample}.bam"

         if [ ! -d "${RES_DIR}/${sample}.bam.bai" ]; then
            samtools index -@ $THREADS "${RES_DIR}/${sample}.bam" > /dev/null
        fi
        
         lofreq call-parallel --pp-threads $THREADS \
             -f "$REF" \
             -o "${RES_DIR}/${sample}.vcf" \
             "${RES_DIR}/${sample}.bam"

         bgzip -c "${RES_DIR}/${sample}.vcf" > "${RES_DIR}/${sample}.vcf.gz" && rm "${RES_DIR}/${sample}.vcf"
         
         tabix -p vcf "${RES_DIR}/${sample}.vcf.gz" > /dev/null
    fi
    
done

# Step 8: Collapse step (skip if newer than inputs)
if [ ! -f "results/collapsed.tsv" ]; then
    : # Will run below, but check idempotency first? 
    # Prompt: "Rebuild only if any input VCF is newer than the TSV."
    
    max_vcf_time=0
    for s in "${SAMPLES[@]}"; do
        t=$(stat -c %Y "${RES_DIR}/${s}.vcf.gz")
        [ "$t" -gt "$max_vcf_time" ] && max_vcf_time=$t
    done
    
    if [ "$(stat -c %Y "results/collapsed.tsv")" -lt "$max_vcf_time" ]; then
         # Rebuild needed (input VCFs changed)
        : 
    else
         continue # Skip collapse step
    fi

fi

# Execute Collapse logic only once when triggered or if file missing/newer than inputs?
# Actually, the check above sets a flag. Let's restructure to ensure we run it exactly once per "change".
# Or simpler: Just always compute if TSV doesn't exist OR is older than max input VCF time.

if [ ! -f "results/collapsed.tsv" ] || \
   [ "$(stat -c %Y 'results/collapsed.tsv')" -lt "$max_vcf_time" ]; then
    
    # Generate data for each sample
    tmpfile=$(mktemp)
    
    for s in "${SAMPLES[@]}"; do
        bcftools query -f '{sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' \
            "${RES_DIR}/${s}.vcf.gz" >> "$tmpfile"
    done
    
    # Write header + data to final file (overwrite if needed)
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "results/collapsed.tsv"
    
    cat "$tmpfile" >> "results/collapsed.tsv"
    rm -f "$tmpfile"
fi

exit 0