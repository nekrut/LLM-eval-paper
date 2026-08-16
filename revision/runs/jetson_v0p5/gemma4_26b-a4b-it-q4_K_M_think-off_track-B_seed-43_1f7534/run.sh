#!/usr/bin/env bash
set -euo pipefail

mkdir -p results

REF="data/ref/chrM.fa"
THREADS=4

if [ ! -f "${REF}.bwt" ]; then
    bwa index "$REF"
fi

if [ ! -f "${REF}.fai" ]; then
    samtools faidx "$REF"
fi

SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

for SAMPLE in "${SAMPLES[@]}"; do
    BAM="results/${SAMPLE}.bam"
    VCF="results/${SAMPLE}.vcf.gz"

    if [ ! -f "$BAM" ]; then
        bwa mem -t "$THREADS" "$REF" \
            "data/raw/${SAMPLE}_1.fq.gz" \
            "data/raw/${SAMPLE}_2.fq.gz" | \
            samtools view -@ "$THREADS" -bS - > "$BAM"
        samtools sort -@ "$THREADS" "$BAM" -o "${BAM}.tmp"
        mv "${BAM}.tmp" "$BAM"
        samtools index "$BATCH_INDEX_FILE" 2>/dev/null || samtools index "$BAM"
    fi

    if [ ! -f "$VCF" ]; then
        lofreq call --rgID "$SAMPLE" --reference "$REF" "$BAM" | \
        bcftools view -v snps | \
        bcftools compress -f -o "$VCF"
        tabix "$VCF"
    fi
done

if [ ! -f "results/collapsed.tsv" ]; then
    printf "sample\tchrom\tpos\tref\talt\taf\n" > results/collapsed.tsv
    for SAMPLE in "${SAMPLES[@]}"; do
        VCF="results/${SAMPLE}.vcf.gz"
        if [ -f "$VCF" ]; then
            bcftools query -f "${SAMPLE}\t%CHROM\t%POS\t%REF\t%ALT\t[%AF]\n" "$VCF" >> results/collapsed.tsv
        fi
    done
fi

exit 0