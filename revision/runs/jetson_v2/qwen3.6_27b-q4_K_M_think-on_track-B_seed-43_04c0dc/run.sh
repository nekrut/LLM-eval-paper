#!/usr/bin/env bash
set -euo pipefail

REF="data/ref/chrM.fa"
RAW_DIR="data/raw"
OUT_DIR="results"
THREADS="${THREADS:-4}"

SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

mkdir -p "$OUT_DIR"

[[ -f "${REF}.bwt" ]] || bwa index "$REF"
[[ -f "${REF}.fai" ]] || samtools faidx "$REF"

for SAMPLE in "${SAMPLES[@]}"; do
    R1="${RAW_DIR}/${SAMPLE}_1.fq.gz"
    R2="${RAW_DIR}/${SAMPLE}_2.fq.gz"
    BAM="${OUT_DIR}/${SAMPLE}.bam"
    BAI="${BAM}.bai"
    VCF="${OUT_DIR}/${SAMPLE}.vcf.gz"
    TBI="${VCF}.tbi"

    if [[ ! -f "$BAI" ]]; then
        bwa mem -t "$THREADS" "$REF" "$R1" "$R2" | \
            samtools view -b -@ "$THREADS" -o "${BAM}.unsorted.bam" -
        samtools sort -@ "$THREADS" -o "$BAM" "${BAM}.unsorted.bam"
        rm -f "${BAM}.unsorted.bam"
        samtools index "$BAM"
    fi

    if [[ ! -f "$TBI" ]]; then
        bcftools mpileup -f "$REF" -O u -@ "$THREADS" -d 250000 "$BAM" | \
            bcftools call -mv -O z -o "$VCF"
        tabix -p vcf "$VCF"
    fi
done

if [[ ! -f "${OUT_DIR}/collapsed.tsv" ]]; then
    {
        printf "sample\tchrom\tpos\tref\talt\taf\n"
        for SAMPLE in "${SAMPLES[@]}"; do
            VCF="${OUT_DIR}/${SAMPLE}.vcf.gz"
            bcftools query -f '%CHROM\t%POS\t%REF\t%ALT[\t%AF]\n' "$VCF" | \
                awk -v s="$SAMPLE" '{print s"\t"$0}'
        done
    } > "${OUT_DIR}/collapsed.tsv"
fi