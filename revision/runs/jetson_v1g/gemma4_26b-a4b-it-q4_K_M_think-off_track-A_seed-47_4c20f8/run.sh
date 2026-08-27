#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
REF="data/ref/chrM.fa"
RESULTS_DIR="results"

mkdir -p "$RESULTS_DIR"

if [[ ! -f "${REF}.fai" ]]; then
    samtools faidx "$REF"
fi

if [[ ! -f "${REF}.bwt" ]]; then
    bwa index "$REF"
fi

for SAMPLE in "${SAMPLES[@]}"; do
    FQ1="data/raw/${SAMPLE}_1.fq.gz"
    FQ2="data/raw/${SAMPLE}_2.fq.gz"
    BAM="$RESULTS_DIR/${SAMPLE}.bam"
    VCF_GZ="$RESULTS_DIR/${SAMPLE}.vcf.gz"
    VCF_TBI="$RESULTS_DIR/${SAMPLE}.vcf.gz.tbi"

    if [[ -f "$VCF_TBI" && "$VCF_TBI" -nt "$FQ1" && "$VCF_TBI" -nt "$FQ2" ]]; then
        continue
    fi

    RG="@RG\tID:${SAMPLE}\tSM:${SAMPLE}\tLB:${SAMPLE}\tPL:ILLUMINA"
    
    bwa mem -t "$THREADS" -R "$RG" "$REF" "$FQ1" "$FQ2" | \
        samtools sort -@ "$THREADS" -o "$BAM"

    if [[ ! -f "${BAM}.bai" ]]; then
        samtools index -@ "$THREADS" "$BAM"
    fi

    VCF_UNCOMPRESSED="$RESULTS_DIR/${SAMPLE}.vcf"
    if [[ ! -f "$VCF_GZ" ]]; then
        lofreq call-parallel --pp-threads "$THREADS" \
            --ref "$REF" \
            --out "$VCF_UNCOMPRESSED" \
            --sig \
            --bonf \
            "$BAM"
        
        bgzip -c "$VCF_UNCOMPRESSED" > "$VCF_GZ"
        tabix -p vcf "$VCF_GZ"
        rm "$VCF_UNCOMPRESSED"
    fi
done

COLLAPSED_TSV="$RESULTS_DIR/collapsed.tsv"
NEEDS_COLLAPSE=false
if [[ ! -f "$COLLAPSED_TSV" ]]; then
    NEEDS_COLLAPSE=true
else
    for SAMPLE in "${SAMPLES[@]}"; do
        VCF_GZ="$RESULTS_DIR/${SAMPLE}.vcf.gz"
        if [[ "$VCF_GZ" -nt "$COLLAPSED_TSV" ]]; then
            NEEDS_COLLAPSE=true
            break
        fi
    done
fi

if [ "$NEEDS_COLLAPSE" = true ]; then
    printf "sample\tchrom\tpos\tref\talt\taf\n" > "$COLLAPSED_TSV"
    for SAMPLE in "${SAMPLES[@]}"; do
        VCF_GZ="$RESULTS_DIR/${SAMPLE}.vcf.gz"
        bcftools query -f "${SAMPLE}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "$VCF_GZ" >> "$COLLAPSED_TSV"
    done
fi

exit 0