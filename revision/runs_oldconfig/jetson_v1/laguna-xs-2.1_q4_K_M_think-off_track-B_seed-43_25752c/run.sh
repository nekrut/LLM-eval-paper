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
    
    fq1="$RAW_DIR/${sample}_1.fq.gz"
    fq2="$RAW_DIR/${sample}_2.fq.gz"
    
    # Align and sort
    bwa mem -t "$THREADS" "$REF" "$fq1" "$fq2" | \
        samtools view -bS - | \
        samtools sort -@ "$THREADS" -o "$bam" -
    
    # Index BAM
    samtools index "$bam"
    
    # Mark duplicates and add read groups for variant calling
    tmp_bam="${bam%.bam}.dedup.bam"
    samtools markdup -r "$bam" "$tmp_bam"
    mv "$tmp_bam" "$bam"
    samtools index "$bam"
    
    # Call variants with lofreq
    lofreq call -f "$REF" -o "${vcf_gz%.gz}" "$bam" && \
        bgzip -c "${vcf_gz%.vcf}" > "$vcf_gz" && \
        tabix -p vcf "$vcf_gz"
    
    rm -f "${vcf_gz%.vcf}"
done

# Create collapsed.tsv with all samples' variants
collapsed="$RESULTS_DIR/collapsed.tsv"
if [[ ! -f "$collapsed" ]]; then
    echo -e "sample\tchrom\tpos\tref\talt\taf" > "$collapsed"
    
    for sample in "${SAMPLES[@]}"; do
        vcf_gz="$RESULTS_DIR/${sample}.vcf.gz"
        if [[ -f "$vcf_gz" ]]; then
            bcftools query -f '%CHROM\t%POS\t%REF\t%ALT[\t%AF]\n' "$vcf_gz" | \
                awk -v sample="$sample" '{print sample"\t"$1"\t"$2"\t"$3"\t"$4"\t"$5}' >> "$collapsed"
        fi
    done
fi

exit 0