#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
REF="data/ref/chrM.fa"
RAW_DIR="data/raw"
OUT_DIR="results"

mkdir -p "$OUT_DIR"

if [[ ! -f "${REF}.fai" ]]; then
    samtools faidx "$REF"
fi

if [[ ! -f "${REF}.bwt" ]]; then
    bwa index "$REF"
fi

for sample in "${SAMPLES[@]}"; do
    F1="${RAW_DIR}/${sample}_1.fq.gz"
    F2="${RAW_DIR}/${sample}_2.fq.gz"
    BAM="${OUT_DIR}/${sample}.bam"
    BAI="${BAM}.bai"
    VCF_GZ="${OUT_DIR}/${sample}.vcf.gz"
    TBI="${VCF_GZ}.tbi"
    VCF_TMP="${OUT_DIR}/${sample}.vcf"

    if [[ -f "$TBI" ]] && [[ "$TBI" -nt "$F1" ]] && [[ "$TBI" -nt "$F2" ]] && [[ "$TBI" -nt "$REF" ]]; then
        continue
    fi

    RG_STR="@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA"

    bwa mem -t "$THREADS" -R "$RG_STR" "$REF" "$F1" "$F2" | \
        samtools sort -@ "$THREADS" -o "$BAM"

    samtools index -@ "$THREADS" "$BAM"

    lofreq call-parallel --pp-threads "$THREADS" "$REF" "$BAM" > "$VCF_TMP"

    bgzip -f "$VCF_TMP"
    tabix -p vcf "$VCF_GZ"
done

COLLAPSED="${OUT_DIR}/collapsed.tsv"
NEEDS_REBUILD=false

if [[ ! -f "$COLLAPSED" ]]; then
    NEEDS_REBUILD=true
else
    for sample in "${SAMPLES[@]}"; do
        TBI="${OUT_DIR}/${sample}.vcf.gz.tbi"
        if [[ "$TBI" -nt "$COLLAPSED" ]]; then
            NEEDS_REBUILD=true
            break
        fi
    done
fi

if [ "$NEEDS_REBUILD" = true ]; then
    printf "sample\tchrom\tpos\tref\talt\taf\n" > "$COLLAPSED"
    for sample in "${SAMPLES[@]}"; do
        bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "${OUT_DIR}/${sample}.vcf.gz" >> "$COLLAPSED"
    done
fi

exit 0