#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
REF="data/ref/chrM.fa"
RESULTS_DIR="results"

mkdir -p "$RESULTS_DIR"

# Reference indexing (once)
if [ ! -f "${REF}.fai" ] || [ "$(stat -c %Y ${REF}.fai 2>/dev/null)" = "0" ]; then
    samtools faidx "$REF" > /dev/null
fi

for sample in "${SAMPLES[@]}"; do
    # Check idempotency for alignment (skip if BAM exists)
    if [ -f "${RESULTS_DIR}/${sample}.bam.bai" ] && \
       ! cmp --silent <(samtools view -H ${RESULTS_DIR}/${sample}.bam | head -10) <(samtools view -H data/raw/${sample}_1.fq.gz 2>/dev/null || true); then
        # Re-alignment check: if BAM exists but input changed or we want to be safe on fresh run, re-align. 
        # However, strict idempotency means skip only if inputs haven't changed significantly and output is valid.
        # Given the constraint "rerunning ... must exit 0 without redoing work", we check existence of final VCF index first as proxy for success.
    fi

    ALN_IN="${sample}_1.fq.gz" "${sample}_2.fq.gz"
    
    if [ -f "${RESULTS_DIR}/${sample}.vcf.gz.tbi" ]; then
        # Already done, skip per-sample steps (idempotency)
        continue
    fi
    
    # Step 3: Alignment with bwa mem using literal backslash-t for RG fields
    bwa mem -t $THREADS \
        -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
        data/raw/${ALN_IN[0]} data/raw/${ALN_IN[1]} | samtools sort -@ $THREADS -o "${RESULTS_DIR}/${sample}.bam"

    # Step 5: BAM indexing
    samtools index -@ $THREADS "${RESULTS_DIR}/${sample}.bam" > /dev/null

    # Step 6: Variant calling with lofreq call-parallel
    lofreq call-parallel --pp-threads $THREADS --verbose \
        --ref "$REF" \
        --out "${RESULTS_DIR}/${sample}.vcf" \
        --sig \
        --bonf \
        "${RESULTS_DIR}/${sample}.bam"

    # Step 7: VCF compression and indexing (remove uncompressed)
    rm -f "${RESULTS_DIR}/${sample}.vcf"
    bgzip -c "${RESULTS_DIR}/${sample}.vcf.gz.tbi" > /dev/null || true; \
        if [ ! -s "${RESULTS_DIR}/${sample}.vcf.gz" ]; then
            # Fallback if bgzip failed or empty (shouldn't happen with lofreq)
            bcftools view -Oz -o "${RESULTS_DIR}/${sample}.vcf.gz" "${RESULTS_DIR}/${sample}.vcf" 2>/dev/null || true; \
                rm -f "${RESULTS_DIR}/${sample}.vcf"; exit 1
        fi; \
    tabix -p vcf "${RESULTS_DIR}/${sample}.vcf.gz" > /dev/null

done

# Step 8: Collapse step -> results/collapsed.tsv
if [ ! -f "$RESULTS_DIR/collapsed.tsv" ]; then
    # Check if any input VCF is newer than TSV (or TSV doesn't exist) to rebuild
    OLDEST_VCF_TS=$(find "${RESULTS_DIR}"/${SAMPLES[@]}/*.vcf.gz 2>/dev/null | xargs -I{} stat -c %Y {} | sort -n | head -1 || echo "0")

    if [ "$OLDEST_VCF_TS" = "0" ]; then
        # No VCFs found, create empty header only? Or error. Assuming valid run means at least one exists.
        : > /dev/null
    fi
    
    {
        printf 'sample\tchrom\tpos\tref\talt\taf\n'
        
        for sample in "${SAMPLES[@]}"; do
            bcftools query -f '{sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' \
                "${RESULTS_DIR}/${sample}.vcf.gz" >> /dev/null || true; \
            
        done
        
    } > "$RESULTS_DIR/collapsed.tsv.tmp"

    mv -f "$RESULTS_DIR/collapsed.tsv.tmp" "$RESULTS_DIR/collapsed.tsv"
fi