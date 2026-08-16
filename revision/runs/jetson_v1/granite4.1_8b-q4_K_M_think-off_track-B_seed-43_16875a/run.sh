#!/usr/bin/env bash
set -euo pipefail

# Define sample names based on filenames in data/raw/
samples=( "M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch" )

# Create results directory if it does not exist
mkdir -p results

# Reference genome file (already decompressed and present in data/ref/)
REF=../ref/chrM.fa

# Loop over each sample pair to perform alignment, sorting, indexing, and variant calling
for samp in "${samples[@]}"; do
    # Uncompressed FASTQ files for paired-end reads
    R1=$(ls ../raw/${samp}_*_1.fq.gz | head -n 1)
    R2=$(ls ../raw/${samp}_*_2.fq.gz | head -n 1)

    # Align reads to the mitochondrial reference using BWA mem
    bwa mem "$REF" "${R1}" "${R2}" > "results/${samp}.sam"

    # Convert SAM to sorted BAM, index BAM, and remove intermediate SAM file
    samtools view -Sb "results/${samp}.sam" | \
        samtools sort -o "results/${samp}.bam"
    samtools index "results/${samp}.bam"
    rm "results/${samp}.sam"

    # Call variants using Lofreq with the mitochondrial reference
    lofreq call --ref "$REF" -o "results/${samp}" "results/${samp}.bam"
    gzip "results/${samp}.vcf"
    tabix -p vcf "results/${samp}.vcf.gz"

    # Move the compressed VCF and its index to the final results directory
    mv "results/${samp}.vcf.gz" "results/${samp}.vcf.gz"
    mv "results/${samp}.vcf.gz.tbi" "results/${samp}.vcf.gz.tbi"
done

# Collapse variant calls across samples into a single TSV file
for samp in "${samples[@]}"; do
    bcftools view -h "results/${samp}.vcf.gz" | \
        grep -v "^#" > "tmp_${samp}.vcf"
    paste <(echo "$samp") <(cut -f 2-6 "tmp_${samp}.vcf") >> results/collapsed.tsv
    rm "tmp_${samp}.vcf"
done

# Header for collapsed TSV file (sample, chrom, pos, ref, alt, af)
echo "sample\tchrom\tpos\tref\talt\taf" > results/collapsed.tsv

# Ensure idempotence: if results/ already contains all expected files, exit successfully
if [ -f results/collapsed.tsv ] && \
   [ -f results/M117-bl.vcf.gz ] && [ -f results/M117-bl.vcf.gz.tbi ] && \
   [ -f results/M117-ch.vcf.gz ] && [ -f results/M117-ch.vcf.gz.tbi ] && \
   [ -f results/M117C1-bl.vcf.gz ] && [ -f results/M117C1-bl.vcf.gz.tbi ] && \
   [ -f results/M117C1-ch.vcf.gz ] && [ -f results/M117C1-ch.vcf.gz.tbi ]; then
    exit 0
fi