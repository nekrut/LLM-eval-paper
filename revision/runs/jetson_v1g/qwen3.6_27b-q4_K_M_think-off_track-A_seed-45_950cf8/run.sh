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

    # Idempotency guard: if final indexed VCF exists, skip sample
    if [[ -f "$TBI" ]]; then
        continue
    fi

    R1="${RAW_DIR}/${SAMPLE}_1.fq.gz"
    R2="${RAW_DIR}/${SAMPLE}_2.fq.gz"

    # Step 3 & 4: Alignment and sorting (idempotent)
    if [[ ! -f "$BAM" ]]; then
        bwa mem -t "$THREADS" \
            -R "@RG\tID:${SAMPLE}\tSM:${SAMPLE}\tLB:${SAMPLE}\tPL:ILLUMINA" \
            "$REF" "$R1" "$R2" | \
        samtools sort -@ "$THREADS" -o "$BAM" -
    fi

    # Step 5: BAM indexing (idempotent)
    if [[ ! -f "$BAI" ]]; then
        samtools index -@ "$THREADS" "$BAM"
    fi

    # Step 6: Variant calling with lofreq call-parallel (idempotent)
    VCF_PLAIN="${OUT_DIR}/${SAMPLE}.vcf"
    if [[ ! -f "$VCF_GZ" ]]; then
        lofreq call-parallel \
            --pp-threads "$THREADS" \
            --ref "$REF" \
            --out "$VCF_PLAIN" \
            "$BAM"
    fi

    # Step 7: VCF compression and indexing (idempotent)
    if [[ ! -f "$TBI" ]]; then
        bgzip -c "$VCF_PLAIN" > "$VCF_GZ"
        tabix -p vcf "$VCF_GZ"
        rm -f "$VCF_PLAIN"
    fi
done

# Step 8: Collapse step -> results/collapsed.tsv
COLLAPSED="${OUT_DIR}/collapsed.tsv"
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
    {
        printf "sample\tchrom\tpos\tref\talt\taf\n"
        for SAMPLE in "${SAMPLES[@]}"; do
            VCF_GZ="${OUT_DIR}/${SAMPLE}.vcf.gz"
            bcftools query -f "${SAMPLE}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "$VCF_GZ"
        done
    } > "$COLLAPSED"
fi