#!/usr/bin/env bash
set -euo pipefail

REF=data/ref/chrM.fa
OUT_DIR=results
declare -a SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

mkdir -p "$OUT_DIR"

for SAMPLE in "${SAMPLES[@]}"; do
    R1="data/raw/${SAMPLE}_1.fq.gz"
    R2="data/raw/${SAMPLE}_2.fq.gz"
    
    # Check if output already exists
    if [ -e "$OUT_DIR/$SAMPLE.bam" ] && [ -e "$OUT_DIR/$SAMPLE.bam.bai" ] && [ -e "$OUT_DIR/$SAMPLE.vcf.gz" ] && [ -e "$OUT_DIR/$SAMPLE.vcf.gz.tbi" ]; then
        continue
    fi

    # Align reads to mitochondrial reference using BWA MEM
    bwa mem "$REF" "$R1" "$R2" | \
    samtools view -bS - > "${OUT_DIR}/${SAMPLE}.bam"

    # Index the BAM file
    samtools sort -@ 4 -o "${OUT_DIR}/${SAMPLE}.sorted.bam" "${OUT_DIR}/${SAMPLE}.bam"
    mv "${OUT_DIR}/${SAMPLE}.sorted.bam" "${OUT_DIR}/${SAMPLE}.bam"
    samtools index "${OUT_DIR}/${SAMPLE}.bam"

    # Call variants using Lofreq
    lofreq call --threads 4 -f "$REF" -o "${OUT_DIR}/${SAMPLE}" "${OUT_DIR}/${SAMPLE}.bam" | \
    bcftools view -Oz > "${OUT_DIR}/${SAMPLE}.vcf.gz"
    bcftools index "${OUT_DIR}/${SAMPLE}.vcf.gz"

    # Extract AF and other info for collapse
    bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\tAF\n' "${OUT_DIR}/${SAMPLE}.vcf.gz" > "${OUT_DIR}/${SAMPLE}_info.tsv"
done

# Collapse the per-sample TSV files into a single table
cat "${OUT_DIR}"/*_info.tsv | sort -k1,1 -k2,2n | uniq > "$OUT_DIR/collapsed.tsv"

exit 0