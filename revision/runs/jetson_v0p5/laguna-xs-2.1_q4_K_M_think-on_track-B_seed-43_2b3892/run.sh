#!/usr/bin/env bash
set -euo pipefail

THREADS=4
REF="data/ref/chrM.fa"
RAW_DIR="data/raw"
RESULTS="results"

mkdir -p "$RESULTS"

# Index reference if not already indexed
if [[ ! -f "${REF}.bwt" ]]; then
    bwa index "$REF"
fi

samples=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

for sample in "${samples[@]}"; do
    bam="${RESULTS}/${sample}.bam"
    vcf_gz="${RESULTS}/${sample}.vcf.gz"
    
    # Skip if all outputs exist
    if [[ -f "$bam" && -f "${bam}.bai" && -f "$vcf_gz" && -f "${vcf_gz}.tbi" ]]; then
        continue
    fi
    
    # Map reads
    bwa mem -t "$THREADS" "$REF" \
        "${RAW_DIR}/${sample}_1.fq.gz" \
        "${RAW_DIR}/${sample}_2.fq.gz" | \
    samtools view -bS - | \
    samtools sort -@ "$THREADS" -o "$bam" -
    
    # Index BAM
    samtools index "$bam"
    
    # Call variants with lofreq
    lofreq mpileup -f "$REF" "$bam" | \
    lofreq call -f "$REF" - -o "${RESULTS}/${sample}.vcf"
    
    # Compress and index VCF
    bcftools view -Oz -o "$vcf_gz" "${RESULTS}/${sample}.vcf"
    tabix -p vcf "$vcf_gz"
    
    rm -f "${RESULTS}/${sample}.vcf"
done

# Create collapsed.tsv
collapsed="${RESULTS}/collapsed.tsv"
if [[ ! -f "$collapsed" ]]; then
    echo -e "sample\tchrom\tpos\tref\talt\taf" > "$collapsed"
    
    for sample in "${samples[@]}"; do
        vcf_gz="${RESULTS}/${sample}.vcf.gz"
        if [[ -f "$vcf_gz" ]]; then
            bcftools query -f '%CHROM\t%POS\t%REF\t%ALT[\t%AF]\n' "$vcf_gz" | \
            awk -v sample="$sample" '{print sample"\t"$0}' >> "$collapsed"
        fi
    done
fi

exit 0