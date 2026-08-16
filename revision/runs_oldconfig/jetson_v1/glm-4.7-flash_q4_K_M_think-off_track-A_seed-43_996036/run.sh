#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
REF="data/ref/chrM.fa"
RAW="data/raw"
RESULTS="results"

mkdir -p "$RESULTS"

# 2. Reference indexing (once)
if [[ ! -f "${REF}.fai" ]]; then
    samtools faidx "$REF"
fi
if [[ ! -f "${REF}.bwt" ]]; then
    bwa index "$REF"
fi

# 3-7. Per-sample workflow
for SAMPLE in "${SAMPLES[@]}"; do
    R1="${RAW}/${SAMPLE}_1.fq.gz"
    R2="${RAW}/${SAMPLE}_2.fq.gz"
    BAM="${RESULTS}/${SAMPLE}.bam"
    BAI="${RESULTS}/${SAMPLE}.bam.bai"
    VCF="${RESULTS}/${SAMPLE}.vcf"
    VCF_GZ="${RESULTS}/${SAMPLE}.vcf.gz"
    VCF_TBI="${RESULTS}/${SAMPLE}.vcf.gz.tbi"

    # Alignment
    if [[ ! -f "$BAI" ]]; then
        bwa mem -t "$THREADS" -R "@RG\tID:${SAMPLE}\tSM:${SAMPLE}\tLB:${SAMPLE}\tPL:ILLUMINA" "$REF" "$R1" "$R2" | \
        samtools sort -@ "$THREADS" -o "$BAM"
    fi

    # BAM Index
    if [[ ! -f "$BAI" ]]; then
        samtools index -@ "$THREADS" "$BAM"
    fi

    # Variant Calling
    if [[ ! -f "$VCF_TBI" ]]; then
        lofreq call-parallel --pp-threads "$THREADS" -f "$REF" "$BAM" -o "$VCF"
    fi

    # VCF Compression and Indexing
    if [[ ! -f "$VCF_TBI" ]]; then
        bgzip -c "$VCF" > "$VCF_GZ"
        tabix -p vcf "$VCF_GZ"
        rm "$VCF"
    fi
done

# 8. Collapse step
COLLAPSED="${RESULTS}/collapsed.tsv"
if [[ ! -f "$COLLAPSED" ]]; then
    {
        echo -e "sample\tchrom\tpos\tref\talt\taf"
        for SAMPLE in "${SAMPLES[@]}"; do
            bcftools query -f '{sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "${RESULTS}/${SAMPLE}.vcf.gz"
        done
    } > "$COLLAPSED"
fi