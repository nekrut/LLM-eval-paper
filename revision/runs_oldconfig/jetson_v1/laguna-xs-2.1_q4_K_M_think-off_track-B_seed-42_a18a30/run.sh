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
    
    # Align reads
    bwa mem -t "$THREADS" "$REF" \
        <(zcat "${RAW_DIR}/${sample}_1.fq.gz") \
        <(zcat "${RAW_DIR}/${sample}_2.fq.gz") | \
    samtools view -bS - | \
    samtools sort -@ "$THREADS" -o "$bam" -
    
    # Index BAM
    samtools index "$bam"
    
    # Mark duplicates and base quality recalibration would be ideal, but for amplicon data we proceed directly to variant calling
    
    # Call variants with lofreq (better for low-frequency variants in amplicon data)
    lofreq mpileup -f "$REF" -t "$THREADS" "$bam" | \
    lofreq call -f "$REF" -o "${RESULTS_DIR}/${sample}.vcf" -
    
    # Compress and index VCF
    bgzip -c "${RESULTS_DIR}/${sample}.vcf" > "$vcf_gz"
    tabix -p vcf "$vcf_gz"
    
    rm -f "${RESULTS_DIR}/${sample}.vcf"
done

# Create collapsed table with allele frequencies from all samples
{
    echo -e "sample\tchrom\tpos\tref\talt\taf"
    for sample in "${SAMPLES[@]}"; do
        vcf_gz="$RESULTS_DIR/${sample}.vcf.gz"
        if [[ -f "$vcf_gz" ]]; then
            # Extract variants with allele frequencies, filter out multi-allelic sites and non-variant sites
            bcftools query -f '%CHROM\t%POS\t%REF\t[%ALT\t%AF\n]' "$vcf_gz" | \
            awk -F'\t' -v sample="$sample" 'NF==5 && $4!="" {print sample"\t"$1"\t"$2"\t"$3"\t"$4"\t"$5}'
        fi
    done > "${RESULTS_DIR}/collapsed.tsv.tmp"
    
    # Sort by chrom, pos and remove duplicates (keep first occurrence)
    sort -k1,1 -k2,2n "${RESULTS_DIR}/collapsed.tsv.tmp" | \
    awk -F'\t' '!seen[$2,$3,$4,$5]++' > "${RESULTS_DIR}/collapsed.tsv"
    
    rm -f "${RESULTS_DIR}/collapsed.tsv.tmp"
}

exit 0