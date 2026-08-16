#!/usr/bin/env bash
set -euo pipefail

THREADS=4
REF="data/ref/chrM.fa"
RAW_DIR="data/raw"
RESULTS="results"

mkdir -p "$RESULTS"

# Index reference if not already indexed
if [ ! -f "${REF}.bwt" ]; then
    bwa index "$REF"
fi

samples=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

for sample in "${samples[@]}"; do
    bam="$RESULTS/${sample}.bam"
    vcf_gz="$RESULTS/${sample}.vcf.gz"
    
    # Check if outputs exist (idempotency)
    if [ -f "$bam" ] && [ -f "$bam.bai" ] && [ -f "$vcf_gz" ] && [ -f "${vcf_gz}.tbi" ]; then
        continue
    fi
    
    # Map and sort BAM
    bwa mem -t "$THREADS" "$REF" "${RAW_DIR}/${sample}_1.fq.gz" "${RAW_DIR}/${sample}_2.fq.gz" | \
        samtools view -bS - | \
        samtools sort -@ "$THREADS" -o "$bam" -
    
    # Index BAM
    samtools index "$bam"
    
    # Call variants with lofreq
    lofreq call -f "$REF" -r "$bam" --pp-threads "$THREADS" -o "${vcf_gz}.tmp" 2>/dev/null || \
        bcftools mpileup -f "$REF" "$bam" | bcftools call -mv -Ov > "${vcf_gz}.tmp.vcf"
    
    # Compress and index VCF
    if [[ "$vcf_gz.tmp" == *.bcf ]]; then
        bcftools view "${vcf_gz}.tmp" -Oz -o "$vcf_gz"
    else
        bgzip -c "${vcf_gz}.tmp.vcf" > "$vcf_gz"
    fi
    
    tabix -p vcf "$vcf_gz"
    
    # Cleanup temp files
    rm -f "${vcf_gz}.tmp" "${vcf_gz}.tmp.vcf"
done

# Create collapsed.tsv
collapsed="$RESULTS/collapsed.tsv"
if [ ! -f "$collapsed" ]; then
    echo -e "sample\tchrom\tpos\tref\talt\taf" > "$collapsed"
    
    for sample in "${samples[@]}"; do
        vcf_gz="$RESULTS/${sample}.vcf.gz"
        if [ -f "$vcf_gz" ]; then
            bcftools query -f '%CHROM\t%POS\t%REF\t[%ALT\t%AD\n]' "$vcf_gz" 2>/dev/null | \
                awk -v sample="$sample" 'BEGIN{FS="\t"; OFS="\t"} {if(NF>=5){af=$5/$4; if(af=="nan") af=0; print sample,$1,$2,$3,$4,sprintf("%.6f",af)}}' >> "$collapsed"
        fi
    done
fi

exit 0