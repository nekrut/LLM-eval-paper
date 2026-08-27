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
    # If VCF.gz and TBI exist, we assume the pipeline for this sample is complete.
    if [[ -f "$VCF_GZ" ]] && [[ -f "$TBI" ]]; then
        continue
    fi

    R1="${RAW_DIR}/${SAMPLE}_1.fq.gz"
    R2="${RAW_DIR}/${SAMPLE}_2.fq.gz"

    # Step 3 & 4: Alignment and Sorting (idempotent)
    if [[ ! -f "$BAM" ]]; then
        bwa mem -t "$THREADS" \
            -R "@RG\tID:${SAMPLE}\tSM:${SAMPLE}\tLB:${SAMPLE}\tPL:ILLUMINA" \
            "$REF" "$R1" "$R2" | \
        samtools sort -@ "$THREADS" -o "$BAM" -
    fi

    # Step 5: BAM Indexing (idempotent)
    if [[ ! -f "$BAI" ]]; then
        samtools index -@ "$THREADS" "$BAM"
    fi

    # Step 6: Variant Calling with lofreq call-parallel
    # We check for the uncompressed VCF or the compressed one. 
    # If neither exists, we run calling.
    if [[ ! -f "${OUT_DIR}/${SAMPLE}.vcf" ]] && [[ ! -f "$VCF_GZ" ]]; then
        lofreq call-parallel \
            --pp-threads "$THREADS" \
            --verbose \
            --ref "$REF" \
            --out "${OUT_DIR}/${SAMPLE}.vcf" \
            "$BAM"
    fi

    # Step 7: VCF Compression and Indexing (idempotent)
    if [[ ! -f "$VCF_GZ" ]]; then
        bgzip -c "${OUT_DIR}/${SAMPLE}.vcf" > "$VCF_GZ"
        rm -f "${OUT_DIR}/${SAMPLE}.vcf"
    fi

    if [[ ! -f "$TBI" ]]; then
        tabix -p vcf "$VCF_GZ"
    fi
done

# Step 8: Collapse step -> results/collapsed.tsv
COLLAPSED="${OUT_DIR}/collapsed.tsv"

# Determine if we need to rebuild collapsed.tsv
# We rebuild if it doesn't exist, or if any VCF.gz is newer than the TSV
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

    for SAMPLE in "${SAMPLES[@]}"; do
        VCF_GZ="${OUT_DIR}/${SAMPLE}.vcf.gz"
        bcftools query -f "${SAMPLE}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "$VCF_GZ" >> "$COLLAPSED"
    done
fi