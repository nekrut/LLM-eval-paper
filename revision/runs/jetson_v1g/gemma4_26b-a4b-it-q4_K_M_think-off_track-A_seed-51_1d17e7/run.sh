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
    FQ1="data/raw/${sample}_1.fq.gz"
    FQ2="data/raw/${sample}_2.fq.gz"
    BAM="$OUT_DIR/${sample}.bam"
    VCF_GZ="$OUT_DIR/${sample}.vcf.gz"
    VCF_TBI="$OUT_DIR/${sample}.vcf.gz.tbi"

    if [[ -f "$VCF_TBI" ]]; then
        continue
    fi

    RG="@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA"
    
    bwa mem -t "$THREADS" -R "$RG" "$REF" "$FQ1" "$FQ2" | \
        samtools sort -@ "$THREADS" -o "$BAM"

    samtools index -@ "$THREADS" "$BAM"

    lofreq call-parallel --pp-threads "$THREADS" \
        --ref "$REF" \
        --out "$OUT_DIR/${sample}.vcf" \
        --sig \
        --bonf \
        "$BAM"

    bgzip -f "$OUT_DIR/${sample}.vcf"
    tabix -p vcf "$VCF_GZ"
done

HEADER="sample	chrom	pos	ref	alt	af"
TMP_TSV=$(mktemp)
echo -e "$HEADER" > "$TMP_TSV"

for sample in "${SAMPLES[@]}"; do
    VCF_GZ="$OUT_DIR/${sample}.vcf.gz"
    bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "$VCF_GZ" >> "$TMP_TSV"
done

mv "$TMP_TSV" "$OUT_DIR/collapsed.tsv"

exit 0