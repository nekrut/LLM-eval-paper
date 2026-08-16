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

    # Idempotency guard: if final indexed VCF exists, skip sample processing
    if [[ -f "$TBI" ]]; then
        continue
    fi

    R1="${RAW_DIR}/${SAMPLE}_1.fq.gz"
    R2="${RAW_DIR}/${SAMPLE}_2.fq.gz"

    # Step 3 & 4: Alignment and sorting
    RG="-R \"@RG\tID:${SAMPLE}\tSM:${SAMPLE}\tLB:${SAMPLE}\tPL:ILLUMINA\""
    
    if [[ ! -f "$BAM" ]]; then
        bwa mem -t "$THREADS" "$REF" "$R1" "$R2" $RG | samtools sort -@ "$THREADS" -o "$BAM" -
    fi

    # Step 5: BAM indexing
    if [[ ! -f "$BAI" ]]; then
        samtools index -@ "$THREADS" "$BAM"
    fi

    VCF="${OUT_DIR}/${SAMPLE}.vcf"

    # Step 6: Variant calling
    if [[ ! -f "$VCF_GZ" ]]; then
        lofreq call-parallel --pp-threads "$THREADS" -f "$REF" -o "$VCF" "$BAM"
        
        # Step 7: Compression and indexing
        bgzip -c "$VCF" > "$VCF_GZ"
        tabix -p vcf "$VCF_GZ"
        
        # Remove intermediate uncompressed VCF
        rm -f "$VCF"
    fi
done

# Step 8: Collapse step
COLLAPSED="${OUT_DIR}/collapsed.tsv"
NEED_COLLAPSE=false

if [[ ! -f "$COLLAPSED" ]]; then
    NEED_COLLAPSE=true
else
    for SAMPLE in "${SAMPLES[@]}"; do
        VCF_GZ="${OUT_DIR}/${SAMPLE}.vcf.gz"
        if [[ "$VCF_GZ" -nt "$COLLAPSED" ]]; then
            NEED_COLLAPSE=true
            break
        fi
    done
fi

if $NEED_COLLAPSE; then
    {
        printf "sample\tchrom\tpos\tref\talt\taf\n"
        for SAMPLE in "${SAMPLES[@]}"; do
            VCF_GZ="${OUT_DIR}/${SAMPLE}.vcf.gz"
            bcftools query -f "${SAMPLE}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "$VCF_GZ"
        done
    } > "$COLLAPSED"
fi