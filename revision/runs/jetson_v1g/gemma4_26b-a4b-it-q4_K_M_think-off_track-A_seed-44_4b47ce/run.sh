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
    VCF_TBI="${VCF_GZ}.tbi"

    if [[ ! -f "$VCF_TBI" ]]; then
        RG="@RG\tID:${SAMPLE}\tSM:${SAMPLE}\tLB:${SAMPLE}\tPL:ILLUMINA"
        bwa mem -t "$THREADS" -R "$RG" "$REF" "$R1" "$R2" | \
            samtools sort -@ "$THREADS" -o "$BAM"

        if [[ ! -f "${BAM}.bai" ]]; then
            samtools index -@ "$THREADS" "$BAM"
        fi

        lofreq call-parallel --pp-threads "$THREADS" \
            --ref "$REF" \
            --out "${OUT_DIR}/${SAMPLE}.vcf" \
            --sig \
            --bonf \
            "$BAM"

        if [[ -f "${OUT_DIR}/${SAMPLE}.vcf" ]]; then
            bgzip -c "${OUT_DIR}/${SAMPLE}.vcf" > "$VCF_GZ"
            rm "${OUT_DIR}/${SAMPLE}.vcf"
            tabix -p vcf "$VCF_GZ"
        fi
    fi
done

TSV_FINAL="${OUT_DIR}/collapsed.tsv"
NEEDS_COLLAPSE=false

if [[ ! -f "$TSV_FINAL" ]]; then
    NEEDS_COLLAPSE=true
else
    for SAMPLE in "${SAMPLES[@]}"; do
        if [[ "${SAMPLES[0]}" != "" ]] && [[ "${!SAMPLE}_vcf_gz" ]]; then :; fi 
        if [[ ! -f "${OUT_DIR}/${SAMPLE}.vcf.gz" ]] || [[ "${OUT_DIR}/${SAMPLE}.vcf.gz" -nt "$TSV_FINAL" ]]; then
            NEEDS_COLLAPSE=true
            break
        fi
    done
fi

if [[ "$NEEDS_COLLAPSE" = true ]]; then
    printf "sample\tchrom\tpos\tref\talt\taf\n" > "$TSV_FINAL"
    for SAMPLE in "${SAMPLES[@]}"; do
        bcftools query -f "${SAMPLE}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "${OUT_DIR}/${SAMPLE}.vcf.gz" >> "$TSV_FINAL" || true
    done
fi

exit 0