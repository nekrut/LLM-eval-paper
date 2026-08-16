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

# 3-5. Per-sample alignment, sorting, indexing
for SAMPLE in "${SAMPLES[@]}"; do
    INPUT_1="${RAW}/${SAMPLE}_1.fq.gz"
    INPUT_2="${RAW}/${SAMPLE}_2.fq.gz"
    BAM="${RESULTS}/${SAMPLE}.bam"
    BAI="${RESULTS}/${SAMPLE}.bam.bai"

    if [[ ! -f "$BAI" ]]; then
        bwa mem -t "$THREADS" -R "@RG\tID:${SAMPLE}\tSM:${SAMPLE}\tLB:${SAMPLE}\tPL:ILLUMINA" "$REF" "$INPUT_1" "$INPUT_2" | samtools sort -@ "$THREADS" -o "$BAM"
        samtools index -@ "$THREADS" "$BAM"
    fi
done

# 6-7. Variant calling, compression, indexing
for SAMPLE in "${SAMPLES[@]}"; do
    VCF="${RESULTS}/${SAMPLE}.vcf"
    VCF_GZ="${RESULTS}/${SAMPLE}.vcf.gz"
    VCF_TBI="${RESULTS}/${SAMPLE}.vcf.gz.tbi"

    if [[ ! -f "$VCF_TBI" ]]; then
        lofreq call-parallel --pp-threads "$THREADS" -f "$REF" "$RESULTS/${SAMPLE}.bam" -o "$VCF"
        bgzip -c "$VCF" > "$VCF_GZ"
        tabix -p vcf "$VCF_GZ"
        rm "$VCF"
    fi
done

# 8. Collapse step
COLLAPSED="${RESULTS}/collapsed.tsv"
COLLAPSED_TMP="${COLLAPSED}.tmp"

if [[ ! -f "$COLLAPSED" ]]; then
    {
        echo -e "sample\tchrom\tpos\tref\talt\taf"
        for SAMPLE in "${SAMPLES[@]}"; do
            bcftools query -f '{sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "$RESULTS/${SAMPLE}.vcf.gz"
        done
    } > "$COLLAPSED_TMP"
    mv "$COLLAPSED_TMP" "$COLLAPSED"
fi