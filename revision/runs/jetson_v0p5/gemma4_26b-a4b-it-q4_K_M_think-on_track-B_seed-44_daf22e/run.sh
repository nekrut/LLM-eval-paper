#!/usr/bin/env bash
set -euo pipefail

THREADS=4
REF="data/ref/chrM.fa"
RAW_DIR="data/raw"
OUT_DIR="results"
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

mkdir -p "$OUT_DIR"

if [[ ! -f "${REF}.bwt" ]]; then
    bwa index "$REF"
fi

if [[ ! -f "${REF}.fai" ]];
then
    samtools faidx "$REF"
fi

for SAMPLE in "${SAMPLES[@]}"; do
    BAM="$OUT_DIR/${SAMPLE}.bam"
    BAI="$BAM.bai"
    VCF="$OUT_DIR/${SAMPLE}.vcf.gz"
    TBI="$VCF.tbi"
    F1="$RAW_DIR/${SAMPLE}_1.fq.gz"
    F2="$RAW_DIR/${SAMPLE}_2.fq.gz"

    if [[ -f "$BAM" && -f "$BAI" && -f "$VCF" && -f "$TBI" ]]; then
        continue
    fi

    bwa mem -t "$THREADS" "$REF" "$F1" "$F2" | \
        samtools sort -@ "$THREADS" -o "$BAM" -
    samtrans_idx=$(samtools index "$BAM")

    VCF_TEMP="$OUT_DIR/${SAMPLE}.vcf"
    lofreq call -f "$REF" -p "$THREADS" -o "$VCF_TEMP" "$BAM"
    bcftools view -Oz -o "$VCF" "$VCF_TEMP"
    tabix -p vcf "$VCF"
    rm "$VCF_TEMP"
done

if [[ ! -f "$OUT_DIR/collapsed.tsv" ]]; then
    TEMP_TSV=$(mktemp)
    printf "sample\tchrom\tpos\tref\talt\taf\n" > "$TEMP_TSV"
    for SAMPLE in "${SAMPLES[@]}"; do
        VCF="$OUT_DIR/${SAMPLE}.vcf.gz"
        if [[ -f "$VCF" ]]; then
            bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "$VCF" | \
                awk -v s="$SAMPLE" '{print s "\t" $0}' >> "$TEMP_TSV"
        fi
    done
    mv "$TEMP_TSV" "$OUT_DIR/collapsed.tsv"
fi

exit 0