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
    
    # Skip if all outputs exist and are non-empty
    if [[ -s "$bam" && -s "${bam}.bai" && -s "$vcf_gz" && -s "${vcf_gz}.tbi" ]]; then
        continue
    fi
    
    # Align reads
    bwa mem -t "$THREADS" "$REF" \
        <(zcat "${RAW_DIR}/${sample}_1.fq.gz") \
        <(zcat "${RAW_DIR}/${sample}_2.fq.gz") | \
    samtools view -bS - | \
    samtools sort -@ "$THREADS" -o "$bam" -
    
    # Index BAM
    samtools index "$bam"
    
    # Mark duplicates and base quality recalibration (optional for amplicon)
    # For simplicity, skip duplicate marking in amplicon data
    
    # Call variants with bcftools
    samtools mpileup -d 10000 -uf "$REF" "$bam" | \
    bcftools call -mv -Ov -o "${RESULTS_DIR}/${sample}.vcf" -
    
    # Compress and index VCF
    bcftools view -Oz -o "$vcf_gz" "${RESULTS_DIR}/${sample}.vcf"
    tabix -p vcf "$vcf_gz"
    
    rm -f "${RESULTS_DIR}/${sample}.vcf"
done

# Create collapsed.tsv with AF calculated from VCFs
{
    echo -e "sample\tchrom\tpos\tref\talt\taf"
    for sample in "${SAMPLES[@]}"; do
        vcf_gz="$RESULTS_DIR/${sample}.vcf.gz"
        if [[ -s "$vcf_gz" ]]; then
            bcftools query -f '%CHROM\t%POS\t%REF\t%ALT[\t%AD]\n' "$vcf_gz" | \
            while IFS=$'\t' read -r chrom pos ref alt ad; do
                # Calculate AF from AD (allele depth)
                if [[ -n "$ad" && "$ad" != "." ]]; then
                    total=$(echo "$ad" | tr ',' '\+' | bc)
                    alt_count=$(echo "$ad" | cut -d',' -f2)
                    af=$(awk "BEGIN {printf \"%.6g\", $alt_count/$total}")
                    printf "%s\t%s\t%s\t%s\t%s\t%s\n" "$sample" "$chrom" "$pos" "$ref" "$alt" "$af"
                fi
            done
        fi
    done
} > "$RESULTS_DIR/collapsed.tsv"