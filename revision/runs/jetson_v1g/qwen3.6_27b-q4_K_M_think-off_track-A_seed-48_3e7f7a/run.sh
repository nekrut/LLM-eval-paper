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
    FQ1="${RAW_DIR}/${SAMPLE}_1.fq.gz"
    FQ2="${RAW_DIR}/${SAMPLE}_2.fq.gz"

    # Step 3 & 4: Alignment and sorting (idempotent)
    if [[ ! -f "$BAM" ]]; then
        bwa mem -t "$THREADS" \
            -R "@RG\tID:${SAMPLE}\tSM:${SAMPLE}\tLB:${SAMPLE}\tPL:ILLUMINA" \
            "$REF" "$FQ1" "$FQ2" | \
            samtools sort -@ "$THREADS" -o "$BAM" -
    fi

    # Step 5: BAM indexing (idempotent)
    if [[ ! -f "$BAI" ]]; then
        samtools index -@ "$THREADS" "$BAM"
    fi

    # Step 6: Variant calling (idempotent)
    # We check for the final compressed VCF to determine if we need to call.
    # If VCF_GZ exists, we assume the whole pipeline for this sample is done.
    if [[ ! -f "$VCF_GZ" ]]; then
        TMP_VCF="${OUT_DIR}/${SAMPLE}.vcf"
        
        # Only run lofreq if the temp vcf doesn't exist or is older than bam
        if [[ ! -f "$TMP_VCF" ]] || [[ "$BAM" -nt "$TMP_VCF" ]]; then
            lofreq call-parallel --pp-threads "$THREADS" \
                --ref "$REF" \
                --out "$TMP_VCF" \
                "$BAM"
        fi

        # Step 7: Compress and Index VCF (idempotent)
        if [[ ! -f "$VCF_GZ" ]]; then
            bgzip -c "$TMP_VCF" > "$VCF_GZ"
            tabix -p vcf "$VCF_GZ"
            rm -f "$TMP_VCF"
        fi
    fi
done

# Step 8: Collapse step (idempotent)
COLLAPSED="${OUT_DIR}/collapsed.tsv"
NEED_COLLAPSE=false

if [[ ! -f "$COLLAPSED" ]]; then
    NEED_COLLAPSE=true
else
    # Check if any input VCF is newer than the collapsed TSV
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