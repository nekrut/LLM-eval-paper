#!/usr/bin/env bash
set -euo pipefail

THREADS=4
REF="data/ref/chrM.fa"
RAW="data/raw"
RESULTS="results"

mkdir -p "$RESULTS"

# Index reference if not already indexed
if [[ ! -f "${REF}.bwt" ]]; then
    bwa index "$REF"
fi

samples=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

for sample in "${samples[@]}"; do
    r1="${RAW}/${sample}_1.fq.gz"
    r2="${RAW}/${sample}_2.fq.gz"
    
    bam="${RESULTS}/${sample}.bam"
    vcf_uncomp="${RESULTS}/${sample}.vcf"
    vcf="${RESULTS}/${sample}.vcf.gz"
    
    # Check if all outputs exist (idempotency)
    if [[ -f "$bam" && -f "${bam}.bai" && -f "${vcf}" && -f "${vcf}.tbi" ]]; then
        continue
    fi
    
    # Map reads with bwa mem
    bwa mem -t "$THREADS" "$REF" <(zcat "$r1") <(zcat "$r2") | \
    samtools view -bS - | \
    samtools sort -@ "$THREADS" -o "${RESULTS}/${sample}.bam.sorted" -
    
    # Rename to final name and mark duplicates
    mv "${RESULTS}/${sample}.bam.sorted" "$bam"
    samtools markdup -r "$bam" "${bam}.dedup"
    mv "${bam}.dedup" "$bam"
    
    # Index BAM
    samtools index "$bam"
    
    # Call variants with lofreq
    lofreq call -b "$bam" -f "$REF" --minDP 30 --callMethod v -q 30 -o "$vcf_uncomp"
    
    # Compress and index VCF
    bgzip -c "$vcf_uncomp" > "$vcf"
    tabix -p vcf "$vcf"
    
    rm -f "$vcf_uncomp"
done

# Create collapsed.tsv from all VCFs
collapsed="${RESULTS}/collapsed.tsv"
if [[ ! -f "$collapsed" ]]; then
    echo -e "sample\tchrom\tpos\tref\talt\taf" > "$collapsed"
    
    for sample in "${samples[@]}"; do
        vcf="${RESULTS}/${sample}.vcf.gz"
        if [[ -f "$vcf" ]]; then
            bcftools query -f '%CHROM\t%POS\t%REF\t%ALT[\t%AF]\n' "$vcf" | \
            awk -v sample="$sample" '{print sample"\t"$0}' >> "$collapsed"
        fi
    done
fi