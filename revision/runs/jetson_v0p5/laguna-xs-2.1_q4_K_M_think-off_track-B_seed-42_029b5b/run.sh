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
    bam="${RESULTS_DIR}/${sample}.bam"
    vcf_gz="${RESULTS_DIR}/${sample}.vcf.gz"
    
    # Skip if all outputs exist and are newer than inputs
    if [[ -f "$bam" && -f "${bam%.gz}.bai" && -f "$vcf_gz" && -f "${vcf_gz%.gz}.tbi" ]]; then
        continue
    fi
    
    # Align reads
    bwa mem -t "$THREADS" "$REF" "${RAW_DIR}/${sample}_1.fq.gz" "${RAW_DIR}/${sample}_2.fq.gz" | \
        samtools view -bS - | \
        samtools sort -@ "$THREADS" -o "$bam" -
    
    # Mark duplicates and index BAM
    tmp_bam="${bam%.bam}.tmp.bam"
    samtools markdup -r "$bam" "$tmp_bam" && mv "$tmp_bam" "$bam"
    samtools index "$bam"
    
    # Call variants with lofreq
    lofreq call -f "$REF" -o "${RESULTS_DIR}/${sample}.vcf" "$bam"
    
    # Compress and index VCF
    bcftools view -Oz -o "$vcf_gz" "${RESULTS_DIR}/${sample}.vcf"
    tabix -p vcf "$vcf_gz"
    
    rm -f "${RESULTS_DIR}/${sample}.vcf"
done

# Create collapsed.tsv with all samples' variants
{
    echo -e "sample\tchrom\tpos\tref\talt\taf"
    for sample in "${SAMPLES[@]}"; do
        vcf_gz="${RESULTS_DIR}/${sample}.vcf.gz"
        if [[ -f "$vcf_gz" ]]; then
            bcftools query -f '%CHROM\t%POS\t%REF\t[%ALT\t%AD]\n' "$vcf_gz" | \
                awk -F'\t' -v sample="$sample" 'NF>=5 { 
                    split($4, ad, ","); 
                    alt=ad[1]; 
                    ref_count=(ad[2]+0); 
                    total=ref_count+alt; 
                    af=(total>0)?alt/total:0; 
                    printf "%s\t%s\t%s\t%s\t%s\t%.6f\n", sample, $1, $2, $3, alt, af 
                }'
        fi
    done
} > "${RESULTS_DIR}/collapsed.tsv"