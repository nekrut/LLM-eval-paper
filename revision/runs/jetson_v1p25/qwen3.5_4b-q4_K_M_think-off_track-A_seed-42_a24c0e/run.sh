#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
REF="data/ref/chrM.fa"
RAW_DIR="data/raw"
RES_DIR="results"

mkdir -p "$RES_DIR" data/ref data/raw 2>/dev/null || true

# --- Step 2: Reference Indexing (once) ---
if [ ! -f "${REF}.faidx" ] && [ ! -d "$(dirname ${REF}).amb" ]; then
    samtools faidx "$REF" --non-recursive >/dev/null 2>&1 || true
    bwa index "$REF" >/dev/null 2>&1 || true
fi

# --- Step 3,4,5: Per-sample Alignment & Sorting (idempotent) ---
for sample in "${SAMPLES[@]}"; do
    if [ -f "${RES_DIR}/${sample}.bam.bai" ]; then
        continue
    fi
    
    fq1="${RAW_DIR}/${sample}_1.fq.gz"
    fq2="${RAW_DIR}/${sample}_2.fq.gz"

    RG_ARG="-R \"@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA\""

    bwa mem -t $THREADS "$REF" <(cat "$fq1" | gzip -dc) <(cat "$fq2" | gzip -dc) 2>/dev/null | samtools sort -@ $THREADS -o "${RES_DIR}/${sample}.bam"
    
    if [ ! -f "${RES_DIR}/${sample}.bai" ]; then
        samtools index -t -@ $THREADS "${RES_DIR}/${sample}.bam" >/dev/null 2>&1 || true
    fi
done

# --- Step 6,7: Variant Calling & Compression (idempotent) ---
for sample in "${SAMPLES[@]}"; do
    if [ ! -f "${RES_DIR}/${sample}.vcf.gz.tbi" ]; then
        lofreq call-parallel --pp-threads $THREADS -f "$REF" -o "${RES_DIR}/${sample}.vcf" "${RES_DIR}/${sample}.bam" >/dev/null 2>&1 || true
        
        if [ ! -s "${RES_DIR}/${sample}.vcf.gz.tbi" ]; then
            bgzip -c "${RES_DIR}/${sample}.vcf" > "${RES_DIR}/${sample}.vcf.gz.tmp" && mv "${RES_DIR}/${sample}.vcf.gz.tmp" "${RES_DIR}/${sample}.vcf.gz" || true
            
            if [ ! -s "${RES_DIR}/${sample}.vcf.gz.tbi" ]; then
                tabix -p vcf -C "$REF" "${RES_DIR}/${sample}.vcf.gz" >/dev/null 2>&1 || true
            fi
            
            rm -f "${RES_DIR}/${sample}.vcf"
        else
            bgzip -c "${RES_DIR}/${sample}.vcf" > "${RES_DIR}/${sample}.vcf.gz.tmp" && mv "${RES_DIR}/${sample}.vcf.gz.tmp" "${RES_DIR}/${sample}.vcf.gz" || true
            
            if [ ! -s "${RES_DIR}/${sample}.vcf.gz.tbi" ]; then
                tabix -p vcf -C "$REF" "${RES_DIR}/${sample}.vcf.gz" >/dev/null 2>&1 || true
            fi
            
            rm -f "${RES_DIR}/${sample}.vcf"
        fi
        
    else
        bgzip -c "${RES_DIR}/${sample}.vcf" > "${RES_DIR}/${sample}.vcf.gz.tmp" && mv "${RES_DIR}/${sample}.vcf.gz.tmp" "${RES_DIR}/${sample}.vcf.gz" || true

        if [ ! -s "${RES_DIR}/${sample}.vcf.gz.tbi" ]; then
            tabix -p vcf -C "$REF" "${RES_DIR}/${sample}.vcf.gz" >/dev/null 2>&1 || true
        fi
        
        rm -f "${RES_DIR}/${sample}.vcf"
    fi
done

# --- Step 8: Collapse (idempotent) ---
if [ ! -s "${RES_DIR}/collapsed.tsv" ]; then
    {
        echo "sample	chrom	pos	ref	alt	af"
        
        for sample in "${SAMPLES[@]}"; do
            bcftools query -f '{CHROM}\t{POS}\t{REF}\t{ALT}\t{INFO/AF\n}' <(bgzip -c "${RES_DIR}/${sample}.vcf.gz") | \
                sed "s/^/${sample}	/" >> /dev/null || true
            
            bcftools query -f '{CHROM}\t{POS}\t{REF}\t{ALT}\t{INFO/AF\n}' <(bgzip -c "${RES_DIR}/${sample}.vcf.gz") | \
                sed "s/^/${sample}	/" >> /dev/null || true
            
        done
        
    } > "${RES_DIR}/collapsed.tsv" 2>/dev/null || true
    
fi