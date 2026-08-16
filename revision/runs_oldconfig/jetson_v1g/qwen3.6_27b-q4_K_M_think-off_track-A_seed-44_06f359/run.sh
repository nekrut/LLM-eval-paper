#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)
REF="data/ref/chrM.fa"
RAW_DIR="data/raw"
OUT_DIR="results"

mkdir -p "$OUT_DIR"

# Step 2: Reference indexing (idempotent)
if [[ ! -f "${REF}.fai" ]] || [[ ! -f "${REF}.bwt" ]]; then
    samtools faidx "$REF"
    bwa index "$REF"
fi

for SAMPLE in "${SAMPLES[@]}"; do
    BAM="${OUT_DIR}/${SAMPLE}.bam"
    BAI="${BAM}.bai"
    VCF_GZ="${OUT_DIR}/${SAMPLE}.vcf.gz"
    TBI="${VCF_GZ}.tbi"

    # Check if final variant artifacts exist and are up-to-date relative to BAM
    # If the final TBI exists, we assume the whole pipeline for this sample is done.
    if [[ -f "$TBI" ]]; then
        continue
    fi

    # Step 3 & 4: Alignment and Sorting
    # Idempotency: skip if BAM exists
    if [[ ! -f "$BAM" ]]; then
        bwa mem -t "$THREADS" \
            -R "@RG\tID:${SAMPLE}\tSM:${SAMPLE}\tLB:${SAMPLE}\tPL:ILLUMINA" \
            "$REF" \
            "${RAW_DIR}/${SAMPLE}_1.fq.gz" \
            "${RAW_DIR}/${SAMPLE}_2.fq.gz" | \
        samtools sort -@ "$THREADS" -o "$BAM" -
    fi

    # Step 5: BAM Indexing
    if [[ ! -f "$BAI" ]]; then
        samtools index -@ "$THREADS" "$BAM"
    fi

    # Step 6: Variant Calling with lofreq
    VCF_PLAIN="${OUT_DIR}/${SAMPLE}.vcf"
    if [[ ! -f "$VCF_GZ" ]]; then
        # Use call-parallel as requested. 
        # Note: lofreq call-parallel expects the BAM file as a positional argument at the end.
        lofreq call-parallel \
            --pp-threads "$THREADS" \
            --verbose \
            --ref "$REF" \
            --out "$VCF_PLAIN" \
            "$BAM"
        
        # Step 7: Compress and Index VCF
        bgzip -c "$VCF_PLAIN" > "$VCF_GZ"
        tabix -p vcf "$VCF_GZ"
        
        # Remove intermediate uncompressed VCF
        rm -f "$VCF_PLAIN"
    fi
done

# Step 8: Collapse step -> results/collapsed.tsv
TSV="${OUT_DIR}/collapsed.tsv"

# Check if TSV needs rebuilding. 
# It needs rebuilding if it doesn't exist, or if any input VCF is newer than the TSV.
NEED_REBUILD=false
if [[ ! -f "$TSV" ]]; then
    NEED_REBUILD=true
else
    for SAMPLE in "${SAMPLES[@]}"; do
        VCF_GZ="${OUT_DIR}/${SAMPLE}.vcf.gz"
        if [[ "$VCF_GZ" -nt "$TSV" ]]; then
            NEED_REBUILD=true
            break
        fi
    done
fi

if $NEED_REBUILD; then
    # Create a temporary file to build the TSV content
    TMP_TSV=$(mktemp)
    
    # Write header
    printf "sample\tchrom\tpos\tref\talt\taf\n" > "$TMP_TSV"
    
    for SAMPLE in "${SAMPLES[@]}"; do
        VCF_GZ="${OUT_DIR}/${SAMPLE}.vcf.gz"
        # bcftools query format: 
        # {sample} is a literal string in the format spec? No, we need to inject the sample name.
        # The prompt says: "the {sample} literal is prepended via the format string so the sample name is attached per row"
        # However, bcftools query -f does not support variable substitution directly in the format string easily without shell expansion.
        # We will use shell expansion to inject the sample name into the format string.
        # Format: '{sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n'
        # Note: %INFO/AF might be empty for some variants. The prompt asks for 'af'.
        
        bcftools query -f "${SAMPLE}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "$VCF_GZ" >> "$TMP_TSV"
    done
    
    mv "$TMP_TSV" "$TSV"
fi