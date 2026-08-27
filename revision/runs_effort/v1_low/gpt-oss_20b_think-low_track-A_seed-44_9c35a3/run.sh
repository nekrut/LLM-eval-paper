#!/usr/bin/env bash
set -euo pipefail

THREADS=4
REF="data/ref/chrM.fa"
RESULTS_DIR="results"

# Create results directory if missing
mkdir -p "$RESULTS_DIR"

# Reference indexing (once)
if [ ! -f "${REF}.amb" ]; then
    bwa index "$REF"
fi
if [ ! -f "${REF}.fai" ]; then
    samtools faidx "$REF"
fi

# Sample list
samples=(M117-bl M117-ch M117C1-bl M117C1-ch)

for sample in "${samples[@]}"; do
    BAM="${RESULTS_DIR}/${sample}.bam"
    BAI="${BAM}.bai"
    VCF_UNCOMP="${RESULTS_DIR}/${sample}.vcf"
    VCF_Z="${VCF_UNCOMP}.gz"
    TBI="${VCF_Z}.tbi"

    # Skip if final VCF index exists
    if [ -f "$TBI" ]; then
        continue
    fi

    # Alignment and sorting
    if [ ! -f "$BAM" ]; then
        bwa mem -t "$THREADS" \
            -R "@RG\\tID:${sample}\\tSM:${sample}\\tLB:${sample}\\tPL:ILLUMINA" \
            "$REF" \
            "data/raw/${sample}_1.fq.gz" \
            "data/raw/${sample}_2.fq.gz" |
        samtools sort -@ "$THREADS" -o "$BAM"
    fi

    # BAM indexing
    if [ ! -f "$BAI" ]; then
        samtools index -@ "$THREADS" "$BAM"
    fi

    # Variant calling with lofreq
    if [ ! -f "$VCF_UNCOMP" ]; then
        lofreq call-parallel --pp-threads "$THREADS" \
            -f "$REF" -b "$BAM" > "$VCF_UNCOMP"
    fi

    # Compress and index VCF
    if [ ! -f "$TBI" ]; then
        bcftools view -O z -o "$VCF_Z" "$VCF_UNCOMP"
        tabix -p vcf "$VCF_Z"
        rm -f "$VCF_UNCOMP"
    fi
done

# Collapse step
COLLAPSED="${RESULTS_DIR}/collapsed.tsv"
needs_rebuild=false
for sample in "${samples[@]}"; do
    VCF_Z="${RESULTS_DIR}/${sample}.vcf.gz"
    if [ ! -f "$VCF_Z" ]; then
        echo "Missing $VCF_Z" >&2
        exit 1
    fi
    if [ ! -f "$COLLAPSED" ] || [ "$VCF_Z" -nt "$COLLAPSED" ]; then
        needs_rebuild=true
        break
    fi
done

if $needs_rebuild; then
    {
        echo -e "sample\tchrom\tpos\tref\talt\taf"
        for sample in "${samples[@]}"; do
            bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" \
                "${RESULTS_DIR}/${sample}.vcf.gz"
        done
    } > "$COLLAPSED.tmp" && mv "$COLLAPSED.tmp" "$COLLAPSED"
fi

exit 0