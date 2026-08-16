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
    samtools faidx "$REF"
fi
if [ ! -d "${REF}.amb" ]; then
    bwa index "$REF"
fi

# Per-sample processing loop
for sample in "${SAMPLES[@]}"; do
    read1="${RAW_DIR}/${sample}_1.fq.gz"
    read2="${RAW_DIR}/${sample}_2.fq.gz"
    
    # Check if all outputs exist and are newer than inputs to skip work (idempotency)
    vcf_tbi="results/${sample}.vcf.gz.tbi"
    bam_bai="results/${sample}.bam.bai"
    ref_idx="${REF}.amb"
    bwa_out_tmp=$(mktemp -d)
    
    if [ ! -e "$vcf_tbi" ] || ([ "$(stat -c %Y $vcf_tbi)" != "0" ] && \
        (( $(date +%s) - 180 ) < "$(stat -c %Y ${read2})" )); then
        
        # Step 3: Alignment with bwa mem using literal backslash-t in RG string
        if [ ! -f "${REF}.amb" ]; then
            echo "Error: Reference index missing for $sample. Skipping." >&2
            exit 1
        fi

        # Construct the exact RG line as required by plan (literal \t)
        rg_line="@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA"
        
        bwa mem -t $THREADS "$REF" <(printf "%s\n%s\n" "${read1}" "${read2}") | samtools sort -@ 4 -o "results/${sample}.bam.tmp"

        # Step 5: BAM indexing
        if [ ! -f "results/${sample}.bam.bai" ]; then
            samtools index -@ $THREADS "results/${sample}.bam.tmp"
        fi
        
        mv "results/${sample}.bam.tmp" "results/${sample}.bam"

        # Step 6: Variant calling with lofreq call-parallel
        if [ ! -f "$vcf_tbi" ]; then
            tmp_vcf="results/.tmp_${sample}_vcf"
            lofreq call-parallel --pp-threads $THREADS \
                --ref "${REF}" "results/${sample}.bam.tmp" > "$tmp_vcf" 2>/dev/null || true
            
            # Step 7: VCF compression and indexing (bgzip + tabix)
            if [ -f "$tmp_vcf" ]; then
                bgzip -c "$tmp_vcf" > "results/${sample}.vcf.gz"
                tabix -p vcf "results/${sample}.vcf.gz"
                
                # Cleanup temp files (remove uncompressed and old bai)
                rm -f "$tmp_vcf"
            fi
            
            mv "results/${sample}.bam.tmp" "results/${sample}.bam"
        else
            # Ensure BAM is up to date if VCF exists but BAM might be stale (simple check: just re-sort if needed, 
            # but per plan we assume inputs are the source of truth. If outputs exist, skip work entirely).
            :
        fi
        
    else
        # All outputs already present and valid; ensure BAM is sorted/indexed for safety in case it's old
        if [ ! -f "results/${sample}.bam.bai" ]; then
             samtools index -@ $THREADS "results/${sample}.bam.tmp" 2>/dev/null || true
        fi
        
    fi
    
done

# Step 8: Collapse step -> results/collapsed.tsv
if [ ! -e "$RES_DIR/collapsed.tsv" ] || ([ "$(stat -c %Y $RES_DIR/collapsed.tsv)" != "0" ] && \
   (( $(date +%s) - 180 ) < "$(stat -c %M ${SAMPLES[3]}_2.fq.gz)" )); then
    
    # Build header and data lines
    {
        printf 'sample\tchrom\tpos\tref\talt\taf\n'
        
        for sample in "${SAMPLES[@]}"; do
            vcf="results/${sample}.vcf.gz"
            if [ -e "$vcf" ]; then
                bcftools query -f '{%s}\t%%CHROM\t%%POS\t%%REF\t%%ALT\t%%INFO/AF\n' "$vcf" 2>/dev/null || true
            fi
        done
        
    } > "$RES_DIR/collapsed.tsv.tmp"

    mv "$RES_DIR/collapsed.tsv.tmp" "$RES_DIR/collapsed.tsv"
fi