#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
REF="data/ref/chrM.fa"
OUT_DIR="results"

mkdir -p "$OUT_DIR"

if [[ ! -f "${REF}.fai" ]]; then
    samtools faidx "$REF"
fi

if [[ ! -f "${REF}.bwt" ]]; then
    bwa index "$REF"
fi

for SAMPLE in "${SAMPLES[@]}"; do
    R1="data/raw/${SAMPLE}_1.fq.gz"
    R2="data/raw/${SAMPLE}_2.fq.gz"
    BAM="${OUT_DIR}/${SAMPLE}.bam"
    VCF_GZ="${OUT_DIR}/${SAMPLE}.vcf.gz"
    TBI="${VCF_GZ}.tbi"

    if [[ -f "$TBI" ]]; then
        if [[ "$R1" -nt "$TBI" || "$R2" -nt "$TBI" ]]; then
            rm -f "$BAM" "$BAM.bai" "$VCF_GZ" "$TBI"
        else
            continue
        fi
    fi

    RG="@RG\tID:${SAMPLE}\tSM:${SAMPLE}\tLB:${SAMPLE}\tPL:ILLUMINA"
    bwa mem -t "$THREADS" -R "$RG" "$REF" "$R1" "$R2" | \
        samtools sort -@ "$THREADS" -o "$BAM"

    samtools index -@ "$THREADS" "$BAM"

    VCF_UNCOMPRESSED="${OUT_DIR}/${SAMPLE}.vcf"
    lofreq call-parallel --pp-threads "$THREADS" --verbose \
        --ref "$REF" --out "$VCF_UNCOMPRESSED" \
        --sig --bonf \
        "$BAM"

    bgzip -c "$VCF_UNCOMPRESSED" > "$VCF_GZ"
    tabix -p vcf "$VCF_GZ"
    rm "$VCF_UNCOMPRESSED"
done

COLLAPSED="${OUT_DIR}/collapsed.tsv"
NEEDS_COLLAPSE=false
if [[ ! -f "$COLLAPSED" ]]; then
    NEEDS_COLLAPSE=true
else
    for SAMPLE in "${SAMPLES[@]}"; do
        if [[ "${OUT_DIR}/${SAMPLE}.vcf.gz.tbi" -nt "$COLLAPSED" ]]; then
            NEEDS_COLLAPSE=true
            break
        fi
    done
fi

if [ "$NEEDS_COLLAPSE" = true ]; then
    printf "sample\tchrom\tpos\tref\talt\taf\n" > "$COLLAPSED"
    for SAMPLE in "${SAMPLES[@]}"; do
        bcftools query -f "${SAMPLE}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "${OUT_DIR}/${SAMPLE}.vcf.gz" >> "$COLLAPSED"
    done
fi

exit 0