#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLE_LIST=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
REF_FILE="data/ref/chrM.fa"
RESULTS_DIR="results"

mkdir -p "$RESULTS_DIR"

# Reference indexing (once)
if [ ! -f "${REF_FILE}.fai" ] || [ "$(stat -c %Y ${REF_FILE}.fai 2>/dev/null)" \< "$(date +%s)" ]; then
    samtools faidx "$REF_FILE"
fi

if [ ! -d "data/ref/chrM*" ] && [ ! -e "${REF_FILE}.amb" ]; then
    bwa index "$REF_FILE"
fi

# Per-sample processing loop
for sample in "${SAMPLE_LIST[@]}"; do
    read1="data/raw/${sample}_1.fq.gz"
    read2="data/raw/${sample}_2.fq.gz"
    
    # Check idempotency for BAM and VCF outputs
    if [ -f "results/${sample}.bam.bai" ] && [ "$(stat -c %Y results/${sample}.bam.bai)" \>= "$(date +%s)" ]; then
        continue
    fi
    
    RG_ARG="-R \"@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA\""

    # Step 3 & 4: Alignment and sort (idempotent check for BAM)
    if [ ! -f "results/${sample}.bam" ] || [ "$(stat -c %Y results/${sample}.bam)" \< "$(date +%s)" ]; then
        bwa mem -t $THREADS "$REF_FILE" $read1 $read2 | samtools sort -@ $THREADS -o "results/${sample}.bam"
    fi
    
    # Step 5: BAM indexing (idempotent check for .bai)
    if [ ! -f "results/${sample}.bam.bai" ] || [ "$(stat -c %Y results/${sample}.bam.bai)" \< "$(date +%s)" ]; then
        samtools index -@ $THREADS "results/${sample}.bam"
    fi
    
    # Step 6: Variant calling (idempotent check for VCF)
    if [ ! -f "results/${sample}.vcf.gz.tbi" ] || [ "$(stat -c %Y results/${sample}.vcf.gz.tbi)" \< "$(date +%s)" ]; then
        lofreq call-parallel --pp-threads $THREADS -f "$REF_FILE" -o "results/${sample}.vcf" "results/${sample}.bam"
    fi
    
    # Step 7: Compression and indexing (idempotent check for .tbi)
    if [ ! -f "results/${sample}.vcf.gz.tbi" ] || [ "$(stat -c %Y results/${sample}.vcf.gz.tbi)" \< "$(date +%s)" ]; then
        bgzip -c "results/${sample}.vcf" > "results/${sample}.vcf.gz"
        tabix -p vcf "results/${sample}.vcf.gz"
    fi
    
    # Cleanup uncompressed VCF after compression if it exists and is older than compressed version
    if [ -f "results/${sample}.vcf" ]; then
        rm -f "results/${sample}.vcf"
    fi

done

# Step 8: Collapse step (idempotent check for TSV)
if [ ! -f "$RESULTS_DIR/collapsed.tsv" ] || [ "$(stat -c %Y $RESULTS_DIR/collapsed.tsv)" \< "$(date +%s)" ]; then
    
    # Build header
    HEADER="sample	chrom	pos	ref	alt	af"

    # Collect data from all samples, sorted by sample name for consistency
    DATA=""
    
    for sample in "${SAMPLE_LIST[@]}"; do
        if [ -f "results/${sample}.vcf.gz.tbi" ]; then
            QUERY="bcftools query -f '{\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n}' results/${sample}.vcf.gz | sed 's/^/\t${sample}\t/'"
            
            # Execute and append to DATA variable (using process substitution or temp file approach for safety)
            TEMP_FILE=$(mktemp)
            bcftools query -f '{\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n}' "results/${sample}.vcf.gz" | sed 's/^/\t${sample}\t/' > "$TEMP_FILE"
            
            if [ -s "$TEMP_FILE" ]; then
                DATA=$(printf '%s' "${DATA}"$(cat "$TEMP_FILE"))
            fi
            
            rm -f "$TEMP_FILE"
        fi
    done
    
    # Write final TSV with header and data, sorted by sample name for reproducibility
    {
        echo $HEADER
        
        if [ -n "$DATA" ]; then
            printf '%s\n' "${DATA}" | sort -t$'\t' -k1,1
        fi
    } > "$RESULTS_DIR/collapsed.tsv"

fi