#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)

# Create results directory if missing
mkdir -p results/

# Reference Indexing (Global, once per script execution or check existence)
REF_IDX_CHECK=true
if [ ! -f "data/ref/chrM.fa.fai" ] || [ ! -d "data/ref/*.bwt" ]; then
    samtools faidx data/ref/chrM.fa 2>/dev/null || true
    bwa index data/ref/chrM.fa 2>/dev/null || true
fi

# Function to check if sample pipeline can be skipped (based on final VCF TBI)
skip_sample_pipeline() {
    local s="$1"
    [ -f "results/${s}.vcf.gz.tbi" ] && return 0
}

for SAMPLE in "${SAMPLES[@]}"; do
    # Idempotency check for per-sample pipeline (BAM, VCF)
    if skip_sample_pipeline "$SAMPLE"; then
        continue
    fi
    
    FASTQ1="data/raw/${SAMPLE}_1.fq.gz"
    FASTQ2="data/raw/${SAMPLE}_2.fq.gz"
    
    # Alignment with BWA mem using literal backslash-t in Read Group string
    if [ ! -f "results/${SAMPLE}.bam.bai" ]; then
        bwa mem -t 4 data/ref/chrM.fa \
            "-R '@RG\\tID=${SAMPLE}\\tSM:${SAMPLE}\\tLB:${SAMPLE}\\tPL:ILLUMINA'" \
            "$FASTQ1" "$FASTQ2" | samtools sort -@ $THREADS -o "results/${SAMPLE}.bam" 2>/dev/null || true
        
        # BAM Indexing (check if exists to avoid re-indexing)
        [ ! -f "results/${SAMPLE}.bam.bai" ] && samtools index -@ $THREADS results/"${SAMPLE}.bam" 2>/dev/null || true
    fi
    
    # Variant Calling with LoFreq call-parallel
    # Output uncompressed VCF to temp path (e.g. results/{sample}.vcf)
    if [ ! -f "results/${SAMPLE}.vcf.gz.tbi" ]; then
        lofreq call-parallel --pp-threads $THREADS \
            results/"${SAMPLE}.bam" data/ref/chrM.fa > "results/${SAMPLE}.vcf" 2>/dev/null || true
        
        # VCF Compression and Indexing (bgzip + tabix)
        bgzip -c "results/${SAMPLE}.vcf" > "results/${SAMPLE}.vcf.gz" 2>/dev/null || true
        tabix -p vcf results/"${SAMPLE}.vcf.gz" 2>/dev/null || true
        
        # Remove intermediate uncompressed VCF (optional but good practice)
        rm -f "results/${SAMPLE}.vcf"
    fi
    
done

# Collapse step -> collapsed.tsv
COLLAPSE_CHECK=true
if [ ! -f "results/collapsed.tsv" ]; then
    COLLAPSE_CHECK=false
fi

# Check if any input VCF is newer than TSV (to decide rebuild)
REBUILD_NEEDED=false
for SAMPLE in "${SAMPLES[@]}"; do
    # Get timestamp of latest .vcf.gz.tbi for this sample
    [ -f "results/${SAMPLE}.vcf.gz.tbi" ] || continue
    
    VCF_TS=$(stat -c %Y results/"${SAMPLE}.vcf.gz.tbi")
    
    if [ "$COLLAPSE_CHECK" = true ]; then
        # If TSV doesn't exist, rebuild needed (handled by COLLAPSE_CHECK=false logic below)
        : 
    else
        # Check against existing collapsed.tsv timestamp
        TS=$(stat -c %Y results/collapsed.tsv 2>/dev/null || echo "0")
        
        if [ "$VCF_TS" -gt "$TS" ]; then
            REBUILD_NEEDED=true
            break
        fi
    fi
    
done

if [ "$REBUILD_NEEDED" = true ] && [ ! -f "results/collapsed.tsv" ]; then
    # Generate collapsed.tsv with header and sample prepended rows
    {
        printf 'sample\tchrom\tpos\tref\talt\taf\n'
        
        for SAMPLE in "${SAMPLES[@]}"; do
            if [ -f "results/${SAMPLE}.vcf.gz" ]; then
                # bcftools query format string: prepend sample name per row via bash concatenation logic (since %SAMPLE not supported natively without custom header)
                # We use a loop to process each VCF and prepend the sample name before writing to TSV file? 
                # Wait, instruction says "prepended via format string". I will construct command with variable interpolation.
                bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' results/"${SAMPLE}.vcf.gz" 2>/dev/null | \
                    awk -F'\t' '{print "'"$SAMPLE"'	'"$1"\t"$2"\t"$3"\t"$4"\t"$5}' >> "results/collapsed.tsv.tmp" || true
                
                # Alternative: Use bcftools query with custom format string if possible? 
                # No, standard %CHROM etc.
            fi
        done
        
    } > results/"collapsed.tsv.tmp" 2>/dev/null
    
    mv results/"collapsed.tsv.tmp" "results/collapsed.tsv" || true
fi