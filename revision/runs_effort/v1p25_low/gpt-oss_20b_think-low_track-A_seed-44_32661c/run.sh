#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
RAW_DIR="data/raw"
REF_DIR="data/ref"
RESULTS_DIR="results"

mkdir -p "$RESULTS_DIR"

# Reference indexing
if [ ! -f "${REF_DIR}/chrM.fa.fai" ]; then
    samtools faidx "${REF_DIR}/chrM.fa"
fi
if [ ! -f "${REF_DIR}/chrM.fa.amb" ]; then
    bwa index "${REF_DIR}/chrM.fa"
fi

# Per-sample processing
for sample in "${SAMPLES[@]}"; do
    BAM="${RESULTS_DIR}/${sample}.bam"
    BAI="${BAM}.bai"
    VCF="${RESULTS_DIR}/${sample}.vcf"
    VCFZ="${VCF}.gz"
    TBZ="${VCFZ}.tbi"

    # Skip if final compressed VCF index exists
    if [ -f "$TBZ" ]; then
        continue
    fi

    # Alignment and sorting
    if [ ! -f "$BAM" ]; then
        bwa mem -t "$THREADS" \
            -R "@RG\\tID:${sample}\\tSM:${sample}\\tLB:${sample}\\tPL:ILLUMINA" \
            "${RAW_DIR}/${sample}_1.fq.gz" "${RAW_DIR}/${sample}_2.fq.gz" |
        samtools sort -@ "$THREADS" -o "$BAM"
    fi

    # BAM index
    if [ ! -f "$BAI" ]; then
        samtools index -@ "$THREADS" "$BAM"
    fi

    # Variant calling
    if [ ! -f "$VCFZ" ]; then
        lofreq call-parallel --pp-threads "$THREADS" \
            -f "${REF_DIR}/chrM.fa" -o "$VCF" "$BAM"

        bgzip -c "$VCF" > "$VCFZ"
        tabix -p vcf "$VCFZ"
        rm -f "$VCF"
    fi
done

# Collapse step
COLLAPSED="${RESULTS_DIR}/collapsed.tsv"
REBUILD=false
for sample in "${SAMPLES[@]}"; do
    VCFZ="${RESULTS_DIR}/${sample}.vcf.gz.tbi"
    if [ ! -f "$COLLAPSED" ] || [ "$(stat -c %Y "$VCFZ")" -gt "$(stat -c %Y "$COLLAPSED")" ]; then
        REBUILD=true
        break
    fi
done

if $REBUILD; then
    {
        echo -e "sample\tchrom\tpos\tref\talt\taf"
        for sample in "${SAMPLES[@]}"; do
            bcftools query -f "${sample}\\t%CHROM\\t%POS\\t%REF\\t%ALT\\t%INFO/AF\n" \
                "${RESULTS_DIR}/${sample}.vcf.gz"
        done
    } > "$COLLAPSED"
fi

exit 0