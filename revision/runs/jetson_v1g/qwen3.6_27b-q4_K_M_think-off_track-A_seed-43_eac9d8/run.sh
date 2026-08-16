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

    # Check if final variant artifacts exist; if so, skip sample processing
    # We check the TBI as it is the last artifact created for a sample before collapse
    if [[ -f "$TBI" ]]; then
        continue
    fi

    # Step 3 & 4: Alignment and Sorting
    # If BAM doesn't exist or is older than FASTQs, re-align
    FQ1="${RAW_DIR}/${SAMPLE}_1.fq.gz"
    FQ2="${RAW_DIR}/${SAMPLE}_2.fq.gz"

    if [[ ! -f "$BAM" ]] || [[ "$FQ1" -nt "$BAM" ]] || [[ "$FQ2" -nt "$BAM" ]]; then
        bwa mem -t "$THREADS" \
            -R "@RG\tID:${SAMPLE}\tSM:${SAMPLE}\tLB:${SAMPLE}\tPL:ILLUMINA" \
            "$REF" "$FQ1" "$FQ2" | \
            samtools sort -@ "$THREADS" -o "$BAM" -
    fi

    # Step 5: BAM Indexing
    if [[ ! -f "$BAI" ]] || [[ "$BAM" -nt "$BAI" ]]; then
        samtools index -@ "$THREADS" "$BAM"
    fi

    # Step 6: Variant Calling with lofreq
    VCF_PLAIN="${OUT_DIR}/${SAMPLE}.vcf"
    
    # Run if plain VCF doesn't exist or BAM is newer
    if [[ ! -f "$VCF_PLAIN" ]] || [[ "$BAM" -nt "$VCF_PLAIN" ]]; then
        lofreq call-parallel \
            --pp-threads "$THREADS" \
            --verbose \
            --ref "$REF" \
            --out "$VCF_PLAIN" \
            "$BAM"
    fi

    # Step 7: VCF Compression and Indexing
    if [[ ! -f "$TBI" ]]; then
        # Compress with bgzip
        bgzip -c "$VCF_PLAIN" > "$VCF_GZ"
        
        # Index with tabix
        tabix -p vcf "$VCF_GZ"
        
        # Remove intermediate uncompressed VCF
        rm -f "$VCF_PLAIN"
    fi
done

# Step 8: Collapse step -> results/collapsed.tsv
COLLAPSED="${OUT_DIR}/collapsed.tsv"

# Check if any input VCF is newer than the collapsed TSV, or if TSV doesn't exist
NEED_REBUILD=false
if [[ ! -f "$COLLAPSED" ]]; then
    NEED_REBUILD=true
else
    for SAMPLE in "${SAMPLES[@]}"; do
        VCF_GZ="${OUT_DIR}/${SAMPLE}.vcf.gz"
        if [[ "$VCF_GZ" -nt "$COLLAPSED" ]]; then
            NEED_REBUILD=true
            break
        fi
    done
fi

if $NEED_REBUILD; then
    # Create header
    printf "sample\tchrom\tpos\tref\talt\taf\n" > "$COLLAPSED"
    
    # Append data from each sample
    for SAMPLE in "${SAMPLES[@]}"; do
        VCF_GZ="${OUT_DIR}/${SAMPLE}.vcf.gz"
        bcftools query -f "${SAMPLE}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "$VCF_GZ" >> "$COLLAPSED"
    done
fi