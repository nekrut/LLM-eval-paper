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

for sample in "${SAMPLES[@]}"; do
    R1="data/raw/${sample}_1.fq.gz"
    R2="data/raw/${sample}_2.fq.gz"
    BAM="${OUT_DIR}/${sample}.bam"
    VCF_GZ="${OUT_DIR}/${sample}.vcf.gz"
    TBI="${VCF_GZ}.tbi"

    if [[ -f "$TBI" ]]; then
        if [[ "$R1" -nt "$TBI" || "$R2" -nt "$TBI" ]]; then
            rm -f "$BAM" "$BAM.bai" "$VCF_GZ" "$TBI"
        else
            continue
        fi
    fi

    RG="@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA"
    bwa mem -t "$THREADS" -R "$RG" "$REF" "$R1" "$R2" | \
        samtools sort -@ "$THREADS" -o "$BAM"

    samtools index -@ "$THREADS" "$BAM"

    lofreq call-parallel --pp-threads "$THREADS" --verbose \
        --ref "$REF" --out "${OUT_DIR}/${sample}.vcf" \
        --sig --bonf "$BAM"

    bgzip -c "${OUT_DIR}/${sample}.vcf" > "$VCF_GZ"
    tabix -p vcf "$VCF_GZ"
    rm "${OUT_DIR}/${sample}.vcf"
done

TSV="${OUT_DIR}/collapsed.tsv"
NEEDS_COLLAPSE=false
if [[ ! -f "$TSV" ]]; then
    NEEDS_COLLAPSE=true
else
    for sample in "${SAMPLES[@]}"; do
        if [[ "${OUT_DIR}/${sample}.vcf.gz.tbi" -nt "$TSV" ]]; then
            NEEDS_COLLAPSE=true
            break
        fi
    done
fi

if [ "$NEEDS_COLLAPSE" = true ]; then
    printf "sample\tchrom\tpos\tref\talt\taf\n" > "$TSV"
    for sample in "${SAMPLES[@]}"; do
        bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "${OUT_DIR}/${sample}.vcf.gz" >> "$TSV"
    done
fi

exit 0