#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)
REF="data/ref/chrM.fa"
RAW_DIR="data/raw"
RES_DIR="results"

mkdir -p "$RES_DIR"

# 2. Reference indexing (idempotent)
if [[ ! -f "${REF}.fai" ]] || [[ ! -f "${REF}.bwt" ]]; then
    samtools faidx "$REF"
    bwa index "$REF"
fi

for SAMPLE in "${SAMPLES[@]}"; do
    BAM="${RES_DIR}/${SAMPLE}.bam"
    BAI="${BAM}.bai"
    VCF_GZ="${RES_DIR}/${SAMPLE}.vcf.gz"
    TBI="${VCF_GZ}.tbi"
    VCF_TMP="${RES_DIR}/${SAMPLE}.vcf"

    # 3 & 4. Alignment and sorting (idempotent)
    if [[ ! -f "$BAM" ]]; then
        bwa mem -t "$THREADS" \
            -R "@RG\tID:${SAMPLE}\tSM:${SAMPLE}\tLB:${SAMPLE}\tPL:ILLUMINA" \
            "$REF" \
            "${RAW_DIR}/${SAMPLE}_1.fq.gz" \
            "${RAW_DIR}/${SAMPLE}_2.fq.gz" | \
        samtools sort -@ "$THREADS" -o "$BAM" -
    fi

    # 5. BAM indexing (idempotent)
    if [[ ! -f "$BAI" ]]; then
        samtools index -@ "$THREADS" "$BAM"
    fi

    # 6. Variant calling (idempotent)
    if [[ ! -f "$VCF_GZ" ]]; then
        lofreq call-parallel \
            --pp-threads "$THREADS" \
            -f "$REF" \
            -o "$VCF_TMP" \
            "$BAM"

        # 7. Compression and indexing
        bgzip -c "$VCF_TMP" > "$VCF_GZ"
        tabix -p vcf "$VCF_GZ"
        rm -f "$VCF_TMP"
    fi
done

# 8. Collapse step (idempotent)
COLLAPSED="${RES_DIR}/collapsed.tsv"
if [[ ! -f "$COLLAPSED" ]]; then
    {
        printf "sample\tchrom\tpos\tref\talt\taf\n"
        for SAMPLE in "${SAMPLES[@]}"; do
            bcftools query -f "${SAMPLE}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "${RES_DIR}/${SAMPLE}.vcf.gz"
        done
    } > "$COLLAPSED"
fi