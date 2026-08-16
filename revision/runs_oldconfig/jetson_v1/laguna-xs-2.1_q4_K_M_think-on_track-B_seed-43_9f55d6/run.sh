#!/usr/bin/env bash
set -euo pipefail

THREADS=4
REF="data/ref/chrM.fa"
RAW_DIR="data/raw"
RESULTS_DIR="results"

mkdir -p "$RESULTS_DIR"

# Check if reference is already indexed
if [[ ! -f "${REF}.bwt" ]]; then
    bwa index "$REF"
fi

samples=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

for sample in "${samples[@]}"; do
    bam="${RESULTS_DIR}/${sample}.bam"
    vcf_gz="${RESULTS_DIR}/${sample}.vcf.gz"
    
    # Check if outputs already exist (idempotency)
    if [[ -f "$bam" && -f "${bam}.bai" && -f "$vcf_gz" && -f "${vcf_gz}.tbi" ]]; then
        continue
    fi
    
    fq1="${RAW_DIR}/${sample}_1.fq.gz"
    fq2="${RAW_DIR}/${sample}_2.fq.gz"
    
    # Map and sort BAM
    bwa mem -t "$THREADS" "$REF" "$fq1" "$fq2" | \
        samtools view -bS - | \
        samtools sort -@ "$THREADS" -o "$bam" -
    
    # Index BAM
    samtools index "$bam"
    
    # Call variants with bcftools
    tmp_vcf="${RESULTS_DIR}/${sample}.vcf.tmp"
    bcftools mpileup -f "$REF" -a FORMAT/DP,FORMAT/AD -Ou "$bam" | \
        bcftools call -mv -Ov -o "$tmp_vcf"
    
    # Compress and index VCF
    bcftools view -Oz -o "$vcf_gz" "$tmp_vcf"
    tabix -p vcf "$vcf_gz"
    
    rm -f "$tmp_vcf"
done

# Create collapsed.tsv with all samples' variants
collapsed="${RESULTS_DIR}/collapsed.tsv"
if [[ ! -f "$collapsed" ]]; then
    echo -e "sample\tchrom\tpos\tref\talt\taf" > "$collapsed"
    
    for sample in "${samples[@]}"; do
        vcf_gz="${RESULTS_DIR}/${sample}.vcf.gz"
        
        # Extract variants with allele frequency, add sample column
        bcftools query -f '%CHROM\t%POS\t%REF\t[%ALT\t%AF\n]' "$vcf_gz" | \
            awk -v sample="$sample" 'BEGIN{FS="\t";OFS="\t"} {print sample,$0}' >> "$collapsed"
    done
fi