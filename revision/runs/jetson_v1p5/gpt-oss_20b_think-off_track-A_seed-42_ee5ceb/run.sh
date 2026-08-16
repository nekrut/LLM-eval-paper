#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

mkdir -p results

# Check if all expected outputs already exist
needs_run=0
for sample in "${SAMPLES[@]}"; do
    for ext in bam bam.bai vcf.gz vcf.gz.tbi; do
        file="results/${sample}.${ext}"
        if [ ! -s "$file" ]; then
            needs_run=1
        fi
    done
done
if [ ! -s results/collapsed.tsv ]; then
    needs_run=1
fi

# If everything is present, exit successfully
if [ $needs_run -eq 0 ]; then
    exit 0
fi

# Reference indexing (idempotent)
if [ ! -f data/ref/chrM.fa.bwt ]; then
    bwa index data/ref/chrM.fa
fi
if [ ! -f data/ref/chrM.fa.fai ]; then
    samtools faidx data/ref/chrM.fa
fi

# Process each sample
for sample in "${SAMPLES[@]}"; do
    bam="results/${sample}.bam"
    bai="results/${sample}.bam.bai"
    vcf_raw="results/${sample}.vcf"
    vcf_gz="results/${sample}.vcf.gz"

    # Alignment and sorting
    if [ ! -s "$bam" ]; then
        bwa mem -t $THREADS -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
            data/ref/chrM.fa data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz | \
            samtools sort -@ $THREADS -o "$bam" -
    fi

    # BAM index
    if [ ! -s "$bai" ]; then
        samtools index -@ $THREADS "$bam"
    fi

    # Variant calling with LoFreq
    if [ ! -s "$vcf_gz" ]; then
        lofreq call-parallel --pp-threads $THREADS -f data/ref/chrM.fa -o "$vcf_raw" "$bam"
        bcftools view -Oz -o "$vcf_gz" "$vcf_raw"
        tabix -p vcf "$vcf_gz"
        rm -f "$vcf_raw"
    fi
done

# Create collapsed.tsv if not present
collapsed="results/collapsed.tsv"
if [ ! -s "$collapsed" ]; then
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed"
fi

# Append per-sample variant data to collapsed.tsv
for sample in "${SAMPLES[@]}"; do
    vcf_gz="results/${sample}.vcf.gz"
    if [ -s "$vcf_gz" ]; then
        bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "$vcf_gz" | \
            awk -v s="$sample" 'BEGIN{OFS="\t"}{print s,$0}' >> "$collapsed"
    fi
done

exit 0