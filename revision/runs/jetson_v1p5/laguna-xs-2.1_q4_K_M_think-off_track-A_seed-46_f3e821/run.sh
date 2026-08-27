#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

mkdir -p results

# Check if reference is already indexed (idempotency)
if [[ ! -f data/ref/chrM.fa.bwt ]]; then
    bwa index data/ref/chrM.fa
fi

if [[ ! -f data/ref/chrM.fa.fai ]]; then
    samtools faidx data/ref/chrM.fa
fi

# Process each sample
for sample in "${SAMPLES[@]}"; do
    bam_file="results/${sample}.bam"
    bai_file="${bam_file}.bai"
    vcf_gz_file="results/${sample}.vcf.gz"
    vcf_tbi_file="${vcf_gz_file}.tbi"

    # Check if all outputs exist (idempotency)
    if [[ -f "$bam_file" && -f "$bai_file" && -f "$vcf_gz_file" && -f "$vcf_tbi_file" ]]; then
        continue
    fi

    # Alignment and sorting
    bwa mem -t $THREADS -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
        data/ref/chrM.fa \
        "data/raw/${sample}_1.fq.gz" \
        "data/raw/${sample}_2.fq.gz" | \
    samtools sort -@ $THREADS -o "$bam_file" -

    # BAM index
    samtools index -@ $THREADS "$bam_file"

    # Variant calling with LoFreq
    lofreq call-parallel --pp-threads $THREADS -f data/ref/chrM.fa \
        -o "results/${sample}.vcf" "$bam_file"

    # Compress and index VCF
    bgzip -f "results/${sample}.vcf"
    tabix -p vcf "$vcf_gz_file"
done

# Create collapsed TSV with header
printf 'sample\tchrom\tpos\tref\talt\taf\n' > results/collapsed.tsv

# Append variants from each sample
for sample in "${SAMPLES[@]}"; do
    bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' \
        "results/${sample}.vcf.gz" | \
    awk -v s="$sample" 'BEGIN{OFS="\t"}{print s,$0}' >> results/collapsed.tsv
done