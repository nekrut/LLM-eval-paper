#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)
REF="data/ref/chrM.fa"
RAW_DIR="data/raw"
RES_DIR="results"

mkdir -p "$RES_DIR"

# Step 2: Reference indexing (idempotent)
if [[ ! -f "${REF}.fai" ]] || [[ ! -f "${REF}.bwt" ]]; then
    samtools faidx "$REF"
    bwa index "$REF"
fi

for SAMPLE in "${SAMPLES[@]}"; do
    BAM="${RES_DIR}/${SAMPLE}.bam"
    BAI="${BAM}.bai"
    VCF_GZ="${RES_DIR}/${SAMPLE}.vcf.gz"
    TBI="${VCF_GZ}.tbi"

    # Check if final variant calling artifact exists and is up-to-date
    # If the .tbi exists, we assume the whole pipeline for this sample is done.
    if [[ -f "$TBI" ]]; then
        continue
    fi

    R1="${RAW_DIR}/${SAMPLE}_1.fq.gz"
    R2="${RAW_DIR}/${SAMPLE}_2.fq.gz"

    # Step 3 & 4: Alignment and Sorting
    # Idempotency check for BAM
    if [[ ! -f "$BAM" ]]; then
        bwa mem -t "$THREADS" \
            -R "@RG\tID:${SAMPLE}\tSM:${SAMPLE}\tLB:${SAMPLE}\tPL:ILLUMINA" \
            "$REF" "$R1" "$R2" | \
        samtools sort -@ "$THREADS" -o "$BAM" -
    fi

    # Step 5: BAM Indexing
    if [[ ! -f "$BAI" ]]; then
        samtools index -@ "$THREADS" "$BAM"
    fi

    # Step 6: Variant Calling
    VCF="${RES_DIR}/${SAMPLE}.vcf"
    if [[ ! -f "$VCF_GZ" ]]; then
        lofreq call-parallel --pp-threads "$THREADS" \
            --ref "$REF" \
            --out "$VCF" \
            "$BAM"
        
        # Step 7: Compression and Indexing
        bgzip -c "$VCF" > "$VCF_GZ"
        tabix -p vcf "$VCF_GZ"
        
        # Remove intermediate uncompressed VCF
        rm -f "$VCF"
    fi
done

# Step 8: Collapse step
COLLAPSED="${RES_DIR}/collapsed.tsv"
NEED_COLLAPSE=false

if [[ ! -f "$COLLAPSED" ]]; then
    NEED_COLLAPSE=true
else
    # Check if any VCF is newer than the collapsed file
    for SAMPLE in "${SAMPLES[@]}"; do
        VCF_GZ="${RES_DIR}/${SAMPLE}.vcf.gz"
        if [[ "$VCF_GZ" -nt "$COLLAPSED" ]]; then
            NEED_COLLAPSE=true
            break
        fi
    done
fi

if $NEED_COLLAPSE; then
    # Create temporary file for body to avoid partial writes
    TMP_BODY=$(mktemp)
    
    for SAMPLE in "${SAMPLES[@]}"; do
        VCF_GZ="${RES_DIR}/${SAMPLE}.vcf.gz"
        bcftools query -f "${SAMPLE}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "$VCF_GZ" >> "$TMP_BODY"
    done
    
    # Combine header and body
    {
        printf "sample\tchrom\tpos\tref\talt\taf\n"
        cat "$TMP_BODY"
    } > "$COLLAPSED"
    
    rm -f "$TMP_BODY"
fi