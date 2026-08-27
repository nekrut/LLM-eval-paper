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
    FQ1="data/raw/${SAMPLE}_1.fq.gz"
    FQ2="data/raw/${SAMPLE}_2.fq.gz"
    BAM="$OUT_DIR/${SAMPLE}.bam"
    VCF_GZ="$OUT_DIR/${SAMPLE}.vcf.gz"
    VCF_TBI="$OUT_DIR/${SAMPLE}.vcf.gz.tbi"

    if [[ -f "$VCF_TBI" && "$VCF_TBI" -nt "$FQ1" && "$VCF_TBI" -nt "$FQ2" ]]; then
        continue
    fi

    RG="@RG\tID:${SAMPLE}\tSM:${SAMPLE}\tLB:${SAMPLE}\tPL:ILLUMINA"
    
    bwa mem -t "$THREADS" -R "$RG" "$REF" "$FQ1" "$FQ2" | \
        samtools sort -@ "$THREADS" -o "$BAM"

    if [[ ! -f "${BAM}.bai" ]]; then
        samtools index -@ "$THREADS" "$BAM"
    fi

    VCF_UNCOMPRESSED="$OUT_DIR/${SAMPLE}.vcf"
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

TSV_OUT="$OUT_DIR/collapsed.tsv"
NEEDS_COLLAPSE=false
for SAMPLE in "${SAMPLES[@]}"; do
    if [[ ! -f "$OUT_DIR/${SAMPLE}.vcf.gz.tbi" ]]; then
        NEEDS_COLLAPSE=true
        break
    fi
    if [[ "$TSV_OUT" != "" && "$OUT_DIR/${SAMPLE}.vcf.gz.tbi" -nt "$TSV_OUT" ]]; then
        NEEDS_COLLAPSE=true
        break
    fi
done

if [ "$NEEDS_COLLAPSE" = true ]; then
    printf "sample\tchrom\tpos\tref\talt\taf\n" > "$TSV_OUT"
    for SAMPLE in "${SAMPLES[@]}"; do
        bcftools query -f "${SAMPLE}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "$OUT_DIR/${SAMPLE}.vcf.gz" >> "$TSV_OUT"
    done
fi

exit 0