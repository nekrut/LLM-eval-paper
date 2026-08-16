#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
REF="data/ref/chrM.fa"
RAW="data/raw"
RESULTS="results"

mkdir -p "$RESULTS"

# Index reference if not already indexed
if [[ ! -f "${REF}.bwt" ]]; then
    bwa index "$REF"
fi

for sample in "${SAMPLES[@]}"; do
    bam="$RESULTS/${sample}.bam"
    vcf_gz="$RESULTS/${sample}.vcf.gz"
    
    # Skip if all outputs exist and are non-empty
    if [[ -s "$bam" && -s "${bam}.bai" && -s "$vcf_gz" && -s "${vcf_gz}.tbi" ]]; then
        continue
    fi
    
    # Align reads
    bwa mem -t "$THREADS" "$REF" \
        "${RAW}/${sample}_1.fq.gz" \
        "${RAW}/${sample}_2.fq.gz" | \
    samtools view -bS - | \
    samtools sort -@ "$THREADS" -o "$bam" -
    
    # Index BAM
    samtools index "$bam"
    
    # Mark duplicates and base quality recalibration (lofreq requires sorted BAM)
    samtools markdup -r "$bam" "$bam.tmp"
    mv "$bam.tmp" "$bam"
    
    # Call variants with lofreq
    lofreq mpileup -f "$REF" "$bam" | \
    lofreq call -f "$REF" -o "${RESULTS}/${sample}.vcf" -
    
    # Compress and index VCF
    bcftools view -Oz -o "$vcf_gz" "${RESULTS}/${sample}.vcf"
    tabix -p vcf "$vcf_gz"
    
    rm -f "${RESULTS}/${sample}.vcf"
done

# Create collapsed.tsv with all samples' variants
{
    echo -e "sample\tchrom\tpos\tref\talt\taf"
    for sample in "${SAMPLES[@]}"; do
        vcf_gz="$RESULTS/${sample}.vcf.gz"
        if [[ -s "$vcf_gz" ]]; then
            bcftools query -f '%CHROM\t%POS\t%REF\t[%ALT\n]' "$vcf_gz" | \
            awk -v sample="$sample" '{print sample"\t"$1"\t"$2"\t"$3"\t"$4}' | \
            while IFS=$'\t' read -r chrom pos ref alt; do
                af=$(bcftools query -f '[%AF\n]' "$vcf_gz" 2>/dev/null | head -n 1)
                if [[ -n "$af" ]]; then
                    printf "%s\t%s\t%s\t%s\t%s\t%s\n" "$sample" "$chrom" "$pos" "$ref" "$alt" "$af"
                fi
            done
        fi
    done | sort -k1,1 -k2,2n -k3,3n
} > "$RESULTS/collapsed.tsv"