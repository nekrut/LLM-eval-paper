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
        "${RAW_DIR}/${sample}_1.fq.gz" \
        "${RAW_DIR}/${sample}_2.fq.gz" | \
    samtools view -bS - | \
    samtools sort -@ "$THREADS" -o "$bam" -
    
    # Index BAM
    samtools index "$bam"
    
    # Mark duplicates and base quality recalibration (optional but good practice)
    # For amplicon data, we'll skip for speed but could add if needed
    
    # Call variants with bcftools
    samtools mpileup -d 10000 -u -f "$REF" "$bam" | \
        bcftools call -mv -Ov -o "${RESULTS_DIR}/${sample}.vcf"
    
    # Filter and compress VCF (keep all variants for amplicon analysis)
    bcftools view "${RESULTS_DIR}/${sample}.vcf" -Oz -o "$vcf_gz"
    tabix -p vcf "$vcf_gz"
    
    rm -f "${RESULTS_DIR}/${sample}.vcf"
done

# Create collapsed.tsv with all samples' variants
echo -e "sample\tchrom\tpos\tref\talt\taf" > "$RESULTS_DIR/collapsed.tsv"

for sample in "${SAMPLES[@]}"; do
    vcf_gz="$RESULTS_DIR/${sample}.vcf.gz"
    
    # Extract variant info and calculate AF
    bcftools query -f '%CHROM\t%POS\t%REF\t%ALT[\t%AD]\n' "$vcf_gz" | \
    while IFS=$'\t' read -r chrom pos ref alt ad; do
        if [[ -n "$ad" && "$ad" != "." ]]; then
            # Parse AD field (format: ref_count,alt_count)
            ref_count=$(echo "$ad" | cut -d',' -f1)
            alt_count=$(echo "$ad" | cut -d',' -f2)
            total=$((ref_count + alt_count))
            if [[ $total -gt 0 ]]; then
                af=$(awk "BEGIN {printf \"%.6f\", $alt_count / $total}")
            else
                af="0.000000"
            fi
            printf "%s\t%s\t%s\t%s\t%s\t%s\n" "$sample" "$chrom" "$pos" "$ref" "$alt" "$af"
        fi
    done >> "$RESULTS_DIR/collapsed.tsv"
done

exit 0