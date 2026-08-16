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
    
    # Skip if all outputs exist
    if [[ -f "$bam" && -f "${bam}.bai" && -f "$vcf_gz" && -f "${vcf_gz}.tbi" ]]; then
        continue
    fi
    
    # Align and sort
    bwa mem -t "$THREADS" "$REF" \
        "${RAW_DIR}/${sample}_1.fq.gz" \
        "${RAW_DIR}/${sample}_2.fq.gz" | \
    samtools view -bS - | \
    samtools sort -@ "$THREADS" -o "$bam" -
    
    # Index BAM
    samtools index "$bam"
    
    # Variant calling with lofreq
    lofreq mpileup -f "$REF" "$bam" | \
    lofreq call -f "$REF" - -o "${bam}.vcf"
    
    # Compress and index VCF
    bcftools view -Oz -o "$vcf_gz" "${bam}.vcf"
    tabix -p vcf "$vcf_gz"
    
    rm -f "${bam}.vcf"
done

# Create collapsed table
echo -e "sample\tchrom\tpos\tref\talt\taf" > "$RESULTS_DIR/collapsed.tsv"

for sample in "${SAMPLES[@]}"; do
    vcf_gz="$RESULTS_DIR/${sample}.vcf.gz"
    
    # Extract variants with allele frequency
    bcftools query -f '%CHROM\t%POS\t%REF\t[%ALT\t%AF]\n' "$vcf_gz" | \
    awk -v sample="$sample" 'BEGIN{OFS="\t"} {print sample, $1, $2, $3, $4, $5}' >> "$RESULTS_DIR/collapsed.tsv"
done