#!/usr/bin/env bash
set -euo pipefail

THREADS=4
REF="data/ref/chrM.fa"
RAW_DIR="data/raw"
RESULTS_DIR="results"

mkdir -p "$RESULTS_DIR"

# Index reference if not already indexed
if [[ ! -f "${REF}.bwt" ]]; then
    bwa index "$REF"
fi

samples=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

for sample in "${samples[@]}"; do
    bam="${RESULTS_DIR}/${sample}.bam"
    vcf_gz="${RESULTS_DIR}/${sample}.vcf.gz"
    
    # Skip if already done
    if [[ -f "$bam" && -f "$bam.bai" && -f "$vcf_gz" && -f "${vcf_gz}.tbi" ]]; then
        continue
    fi
    
    fq1="${RAW_DIR}/${sample}_1.fq.gz"
    fq2="${RAW_DIR}/${sample}_2.fq.gz"
    
    # Map and create sorted BAM
    bwa mem -t "$THREADS" "$REF" "$fq1" "$fq2" | \
        samtools sort -@ "$THREADS" -o "$bam" -
    
    # Index BAM
    samtools index "$bam"
    
    # Call variants and create compressed VCF with AF
    bcftools mpileup -f "$REF" "$bam" | \
        bcftools call -mv -a FORMAT/AF -Ov | \
        bgzip > "$vcf_gz"
    
    tabix -p vcf "$vcf_gz"
done

# Create collapsed.tsv with all variants across samples
{
    echo -e "sample\tchrom\tpos\tref\talt\taf"
    for sample in "${samples[@]}"; do
        vcf_gz="${RESULTS_DIR}/${sample}.vcf.gz"
        if [[ -f "$vcf_gz" ]]; then
            bcftools query -f '%CHROM\t%POS\t%REF\t%ALT[\t%SAMPLE\t%AF=%INFO/AF\n]' "$vcf_gz" | \
                awk -F'\t' -v sample="$sample" 'NF>=6 {print sample"\t"$1"\t"$2"\t"$3"\t"$4"\t"$5}'
        fi
    done
} > "${RESULTS_DIR}/collapsed.tsv"