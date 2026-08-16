#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
REF="data/ref/chrM.fa"
RAW_DIR="data/raw"
RESULTS_DIR="results"

mkdir -p "$RESULTS_DIR"

# Index reference if not already indexed
if [[ ! -f "${REF}.bwt" ]]; then
    bwa index "$REF"
fi

for sample in "${SAMPLES[@]}"; do
    bam="$RESULTS_DIR/${sample}.bam"
    vcf_gz="$RESULTS_DIR/${sample}.vcf.gz"
    
    # Skip if all outputs exist (idempotent)
    if [[ -f "$bam" && -f "${bam}.bai" && -f "$vcf_gz" && -f "${vcf_gz}.tbi" ]]; then
        continue
    fi
    
    # Align and sort
    bwa mem -t "$THREADS" "$REF" \
        <(zcat "${RAW_DIR}/${sample}_1.fq.gz") \
        <(zcat "${RAW_DIR}/${sample}_2.fq.gz") | \
    samtools view -b - | \
    samtools sort -@ "$THREADS" -o "$bam" -
    
    # Index BAM
    samtools index "$bam"
    
    # Mark duplicates and base quality recalibration (optional for amplicon)
    # For simplicity, skip duplicate marking in amplicon data
    
    # Variant calling with bcftools mpileup + call
    samtools mpileup -a DP4 -d 200 --min-map-quality 30 -f "$REF" "$bam" | \
    bcftools call -mv -Ov -o "${RESULTS_DIR}/${sample}.vcf" -
    
    # Compress and index VCF
    bcftools view -Oz -o "$vcf_gz" "${RESULTS_DIR}/${sample}.vcf"
    tabix -p vcf "$vcf_gz"
    
    rm -f "${RESULTS_DIR}/${sample}.vcf"
done

# Create collapsed.tsv with all samples' variants
{
    echo -e "sample\tchrom\tpos\tref\talt\taf"
    for sample in "${SAMPLES[@]}"; do
        vcf_gz="$RESULTS_DIR/${sample}.vcf.gz"
        if [[ -f "$vcf_gz" ]]; then
            bcftools query -f '%CHROM\t%POS\t%REF\t%ALT[\t%AF]\n' "$vcf_gz" | \
            awk -v sample="$sample" '{print sample"\t"$1"\t"$2"\t"$3"\t"$4"\t"$5}'
        fi
    done
} > "$RESULTS_DIR/collapsed.tsv"