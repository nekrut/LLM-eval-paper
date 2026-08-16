#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
REF="data/ref/chrM.fa"
RAW_DIR="data/raw"
OUT_DIR="results"

mkdir -p "$OUT_DIR"

[[ -f "${REF}.bwt" ]] || bwa index "$REF"
[[ -f "${REF}.fai" ]] || samtools faidx "$REF"

for sample in "${SAMPLES[@]}"; do
    BAM="${OUT_DIR}/${sample}.bam"
    BAI="${BAM}.bai"
    VCF="${OUT_DIR}/${sample}.vcf"
    VCF_GZ="${VCF}.gz"
    TBI="${VCF_GZ}.tbi"

    [[ -f "$BAM" ]] || {
        bwa mem -t "$THREADS" \
            -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
            "$REF" \
            "${RAW_DIR}/${sample}_1.fq.gz" \
            "${RAW_DIR}/${sample}_2.fq.gz" | \
        samtools sort -@ "$THREADS" -o "$BAM" -
    }

    [[ -f "$BAI" ]] || samtools index -@ "$THREADS" "$BAM"

    [[ -f "$VCF" || -f "$VCF_GZ" ]] || {
        lofreq call-parallel --pp-threads "$THREADS" -f "$REF" -o "$VCF" "$BAM"
    }

    [[ -f "$TBI" ]] || {
        if [[ -f "$VCF" ]]; then bgzip -f "$VCF"; fi
        tabix -p vcf "$VCF_GZ"
    }
done

printf 'sample\tchrom\tpos\tref\talt\taf\n' > "${OUT_DIR}/collapsed.tsv"
for sample in "${SAMPLES[@]}"; do
    bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "${OUT_DIR}/${sample}.vcf.gz" | \
        awk -v s="$sample" 'BEGIN{OFS="\t"}{print s,$0}' >> "${OUT_DIR}/collapsed.tsv"
done