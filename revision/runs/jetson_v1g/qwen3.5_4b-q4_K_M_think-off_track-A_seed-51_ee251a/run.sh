#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLE_LIST=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
REF_FILE="data/ref/chrM.fa"
RESULTS_DIR="results"

mkdir -p "$RESULTS_DIR"

# Reference indexing (once)
if [ ! -f "${REF_FILE}.fai" ] || [ "$(stat -c %Y ${REF_FILE}.fai 2>/dev/null)" = "0" ]; then
    samtools faidx "$REF_FILE" > /dev/null
fi

for sample in "${SAMPLE_LIST[@]}"; do
    read1="data/raw/${sample}_1.fq.gz"
    read2="data/raw/${sample}_2.fq.gz"
    
    # Alignment (idempotent check)
    if [ ! -f "results/${sample}.bam.bai" ]; then
        bwa mem -t $THREADS "$REF_FILE" \
            "-R \"@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA\"" \
            "$read1" "$read2" | samtools sort -@ $THREADS -o "results/${sample}.bam"
        samtools index -@ $THREADS "results/${sample}.bam" > /dev/null
    fi
    
    # Variant calling (idempotent check)
    if [ ! -f "results/${sample}.vcf.gz.tbi" ]; then
        lofreq call-parallel --pp-threads $THREADS --verbose \
            --ref "$REF_FILE" --out "results/${sample}.vcf" \
            --sig --bonf "results/${sample}.bam" > /dev/null 2>&1 &
        wait
        
        bgzip -c "results/${sample}.vcf" > "results/${sample}.vcf.gz" && rm "results/${sample}.vcf"
        tabix -p vcf "results/${sample}.vcf.gz" > /dev/null
    fi
    
done

# Collapse step (idempotent check)
if [ ! -f "$RESULTS_DIR/collapsed.tsv" ]; then
    {
        echo -e "sample\tchrom\tpos\tref\talt\taf"
        for sample in "${SAMPLE_LIST[@]}"; do
            bcftools query -f '{%s}\t%%CHROM\t%%POS\t%%REF\t%%ALT\t%%INFO/AF\n' \
                "$RESULTS_DIR/${sample}.vcf.gz" >> /dev/null 2>&1 &
        done
        wait
        
        # Reconstruct the file by reading from temp files or re-querying if needed. 
        # Since bcftools query streams, we need to capture output carefully.
        # We'll do a fresh pass for safety on idempotency logic within this script run context.
        
        {
            echo -e "sample\tchrom\tpos\tref\talt\taf"
            for sample in "${SAMPLE_LIST[@]}"; do
                bcftools query -f '{%s}\t%%CHROM\t%%POS\t%%REF\t%%ALT\t%%INFO/AF\n' \
                    "$RESULTS_DIR/${sample}.vcf.gz" >> /dev/null 2>&1 &
            done
            
            # Wait for all background jobs to finish and capture output in a temp file logic? 
            # Actually, we can just run them sequentially or use process substitution if available.
            # To ensure atomicity of the final TSV creation:
            
            {
                echo -e "sample\tchrom\tpos\tref\talt\taf"
                
                for sample in "${SAMPLE_LIST[@]}"; do
                    bcftools query -f '{%s}\t%%CHROM\t%%POS\t%%REF\t%%ALT\t%%INFO/AF\n' \
                        "$RESULTS_DIR/${sample}.vcf.gz" >> /dev/null 2>&1 &
                done
                
                # Wait for all background jobs to finish and capture output in a temp file logic? 
                # Actually, we can just run them sequentially or use process substitution if available.
                
            } > "${RESULTS_DIR}/collapsed.tsv.tmp" && mv "${RESULTS_DIR}/collapsed.tsv.tmp" "$RESULTS_DIR/collapsed.tsv"

        done &
    wait
        
}