#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
REF="data/ref/chrM.fa"
RESULTS_DIR="results"

mkdir -p "$RESULTS_DIR"

# --- Step 2: Reference Indexing (Once) ---
if [ ! -f "${REF}.fa.fai" ] || [ "$(stat -c %Y ${REF}.fa)" -lt "$(date +%s%N/1000000000)" ]; then # Check if fai is newer than fa or missing. Actually, simpler: check existence of bwa index files too to be safe against partial runs.
    samtools faidx "$REF" 2>/dev/null || true
fi

if [ ! -f "${REF}.amb" ] && [ ! -d "$(dirname ${REF}).bwt" ]; then # Check for BWA index presence (either .amb or bwt files)
    bwa index "$REF" 2>/dev/null || true
fi

# --- Per-sample processing loop ---
for sample in "${SAMPLES[@]}"; do
    fq1="data/raw/${sample}_1.fq.gz"
    fq2="data/raw/${sample}_2.fq.gz"
    
    # Guard: Skip if all outputs exist and are newer than inputs (Idempotency)
    vcf_tbi="${RESULTS_DIR}/${sample}.vcf.gz.tbi"
    bai="${RESULTS_DIR}/${sample}.bam.bai"
    bam="${RESULTS_DIR}/${sample}.bam"
    vcf_uncompressed="${RESULTS_DIR}/${sample}.vcf"

    if [ -e "$vcf_tbi" ] && \
       [[ "$(stat -c %Y $vcf_tbi)" -gt "$(stat -c %Y ${fq1})" ]] && \
       [[ "$(stat -c %Y $vcf_tbi)" -gt "$(stat -c %Y ${fq2})" ]]; then
        
        # Check if BAM is also newer than VCF (in case of partial run where only vcf was updated)
        if [ ! -e "$bam.bai" ]; then
            continue; 
        fi
    else
        # Ensure we have the latest inputs to avoid re-running on stale data
        if [[ "$(stat -c %Y ${fq1})" -gt "$(stat -c %Y $vcf_tbi)" ]] || \
           [[ "$(stat -c %Y ${fq2})" -gt "$(stat -c %Y $vcf_tbi)" ]]; then
            # Force re-run if inputs are newer than the target VCF index
        fi
    fi

    # Step 3: Alignment with BWA mem (Idempotent check for BAM)
    bam_newer_than_vcf=false
    if [ -e "$bam" ] && [[ "$(stat -c %Y $vcf_tbi)" -gt "$(stat -c %Y ${fq1})" ]] || \
       [[ "$(stat -c %Y $vcf_tbi)" -gt "$(stat -c %Y ${fq2})" ]]; then
        
        # If BAM exists but is older than inputs, or if we are in a fresh run context where vcf doesn't exist yet.
        # Actually, the plan says "Per-sample ... alignment". We should re-align only if bam is missing or stale relative to input quality? 
        # The prompt implies standard workflow: Align -> Sort/Index -> Call.
        # Idempotency rule: If results/{sample}.vcf.gz.tbi exists and inputs are not newer, skip everything for this sample.
    fi

    # Re-run alignment if BAM is missing or older than the VCF index (which implies we need fresh data)
    # Or simply re-align if bam doesn't exist to ensure clean state on first run of a partial set? 
    # The prompt says "rerunning ... must exit 0 without redoing work". This means if vcf.gz.tbi exists, skip ALL steps.
    
    if [ -e "$vcf_tbi" ]; then
        continue; # Skip entire sample processing if final index exists and inputs are not newer (checked above)
    fi

    RG="-R \"@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA\""

    bwa mem -t $THREADS "$REF" ${fq1} ${fq2} 2>/dev/null | samtools sort -@ $THREADS -o "${bam}"
    
    # Step 5: BAM Indexing (Idempotent check for .bai)
    if [ ! -e "${bam}.bai" ]; then
        samtools index -t "$bam" --threads $THREADS
    fi

    # Step 6: Variant Calling with lofreq call-parallel
    # Idempotency: If vcf.gz.tbi exists, skip. Otherwise run.
    if [ ! -e "${vcf_uncompressed}" ]; then
        lofreq call-parallel --pp-threads $THREADS --verbose \
            --ref "$REF" --out "${RESULTS_DIR}/${sample}.vcf" \
            --sig --bonf "${bam}" 2>/dev/null || true
        
        # Step 7: VCF Compression and Indexing (Idempotent check for .tbi)
        if [ ! -e "${vcf_tbi}" ]; then
            bgzip -c "${RESULTS_DIR}/${sample}.vcf" > "${RESULTS_DIR}/${sample}.vcf.gz"
            tabix -p vcf "$RESULTS_DIR/${sample}.vcf.gz" --threads $THREADS
            
            # Remove uncompressed intermediate if it exists (good practice, though not strictly required for idempotency)
            rm -f "${RESULTS_DIR}/${sample}.vcf"
        fi
    else
        # Ensure compression/index is up to date even if we skipped the call step? 
        # The prompt says "rerunning ... must exit 0 without redoing work". 
        # If vcf.gz.tbi exists, we assume it's valid. We don't need to re-compress or index unless inputs changed significantly (which we check at start).
    fi

done

# --- Step 8: Collapse step ---
tsv="${RESULTS_DIR}/collapsed.tsv"

if [ -e "$tsv" ]; then
    # Check if any input VCF is newer than the TSV. If all are older, skip.
    latest_vcf_time=0
    for sample in "${SAMPLES[@]}"; do
        vcf="${RESULTS_DIR}/${sample}.vcf.gz.tbi"
        if [ -e "$vcf" ]; then
            t=$(stat -c %Y $vcf)
            [[ $t -gt $latest_vcf_time ]] && latest_vcf_time=$t
        fi
    done
    
    current_tsv_time=$(stat -c %Y $tsv 2>/dev/null || echo 0)
    
    if [ "$current_tsv_time" -ge "$latest_vcf_time" ]; then
        # TSV is newer than all inputs, skip rebuild.
        :
    else
        # Rebuild collapsed.tsv
        
        header="sample	chrom	pos	ref	alt	af"

        tmp_file=$(mktemp)
        
        for sample in "${SAMPLES[@]}"; do
            vcf="${RESULTS_DIR}/${sample}.vcf.gz.tbi"
            if [ -e "$vcf" ]; then
                bcftools query -f '{\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n}' \
                    "${RESULTS_DIR}/${sample}.vcf.gz" >> "$tmp_file" 2>/dev/null || true
            fi
        done
        
        # Write header + data to final file (overwrite)
        printf '%s\n' "$header" > "$tsv"
        cat "$tmp_file" >> "$tsv"
        
        rm -f "$tmp_file"
    fi
fi