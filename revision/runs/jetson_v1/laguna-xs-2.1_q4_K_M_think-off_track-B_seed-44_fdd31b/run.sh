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
    
    # Mark duplicates and base quality recalibration (optional, skip for speed)
    # Call variants with lofreq
    lofreq mpileup -f "$REF" "$bam" | \
    lofreq call -f "$REF" - -o "${RESULTS_DIR}/${sample}.vcf"
    
    # Convert to VCF.gz and index
    bcftools view "${RESULTS_DIR}/${sample}.vcf" -Oz -o "$vcf_gz"
    tabix -p vcf "$vcf_gz"
    
    rm -f "${RESULTS_DIR}/${sample}.vcf"
done

# Create collapsed.tsv with all variants across samples
{
    echo -e "sample\tchrom\tpos\tref\talt\taf"
    for sample in "${SAMPLES[@]}"; do
        vcf_gz="$RESULTS_DIR/${sample}.vcf.gz"
        if [[ -s "$vcf_gz" ]]; then
            bcftools query -f '%CHROM\t%POS\t%REF\t[%ALT]\t[%AF]\n' "$vcf_gz" | \
            awk -v sample="$sample" '{print sample"\t"$1"\t"$2"\t"$3"\t"$4"\t"$5}'
        fi
    done > "${RESULTS_DIR}/collapsed.tsv.tmp"
    
    # Sort and deduplicate if needed, then finalize
    sort -k1,1 -k2,2n "${RESULTS_DIR}/collapsed.tsv.tmp" > "$RESULTS_DIR/collapsed.tsv"
    rm -f "${RESULTS_DIR}/collapsed.tsv.tmp"
}

exit 0