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

    if [[ -f "$TBI" && "$TBI" -nt "${REF}" && "$TBI" -nt "$R1" && "$TBI" -nt "$R2" ]]; then
        continue
    fi

    RG="@RG\tID:${SAMPLE}\tSM:${SAMPLE}\tLB:${SAMPLE}\tPL:ILLUMINA"
    
    bwa mem -t "$THREADS" -R "$RG" "$REF" "$R1" "$R2" | \
        samtools sort -@ "$THREADS" -o "$BAM"

    if [[ ! -f "${BAM}.bai" ]]; then
        samtools index -@ "$THREADS" "$BAM"
    fi

    VCF_UNCOMPRESSED="${OUT_DIR}/${SAMPLE}.vcf"
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

TSV="$OUT_DIR/collapsed.tsv"
NEEDS_TSV=true
for SAMPLE in "${SAMPLES[@]}"; do
    if [[ ! -f "${OUT_DIR}/${SAMPLE}.vcf.gz.tbi" ]]; then
        NEEDS_TSV=false
        break
    fi
done

if [ "$NEEDS_TSV" = true ] && [[ -f "$TSV" ]]; then
    LATEST_VCF=$(ls -t "${OUT_DIR}"/*.vcf.gz | head -n 1)
    if [[ "$TSV" -nt "$LATEST_VCF" ]]; then
        NEEDS_TSV=false
    fi
fi

if [ "$NEEDS_TSV" = true ]; then
    printf "sample\tchrom\tpos\tref\talt\taf\n" > "$TSV"
    for SAMPLE in "${SAMPLES[@]}"; do
        bcftools query -f "${SAMPLE}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "${OUT_DIR}/${SAMPLE}.vcf.gz" >> "$TSV"
    done
fi

exit 0