#!/usr/bin/env bash
set -euo pipefail

# Define sample names based on filenames in data/raw/
samples=( "M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch" )

# Create results directory if it does not exist
mkdir -p results

# Loop over each sample pair and perform alignment, sorting, indexing, and variant calling
for samp in "${samples[@]}"; do
    # Uncompress paired-end FASTQ files (assuming gzip compression)
    fq1="data/raw/${samp}_1.fq.gz"
    fq2="data/raw/${samp}_2.fq.gz"
    gzcat "$fq1" "$fq2" | \
    
    # Align reads to mitochondrial reference using BWA MEM
    bwa mem -t 4 data/ref/chrM.fa /dev/stdin > "results/${samp}.sam"
    
    # Convert SAM to sorted BAM, index it, and remove the SAM file
    samtools view -Sb "results/${samp}.sam" | \
        samtools sort -@ 4 -o "results/${samp}.bam"
    samtools index "results/${samp}.bam"
    rm "results/${samp}.sam"
    
    # Call variants using Lofreq on the sorted BAM
    lofreq call -f data/ref/chrM.fa -o "results/${samp}.vcf.gz" "results/${samp}.bam"
    bcftools index "results/${samp}.vcf.gz"
done

# Extract variant information and collapse into a single TSV file
echo "sample chrom pos ref alt af" > results/collapsed.tsv
for samp in "${samples[@]}"; do
    # Parse Lofreq VCF to extract required columns (pos, REF, ALT, AF)
    bcftools view -H "results/${samp}.vcf.gz" | \
        while IFS= read -r line; do
            chrom=$(echo "$line" | grep -oP '(?<=CHROM\t)[^ ]+')
            pos=$(echo "$line" | grep -oP '(?<=POS\t)[0-9]+')
            ref=$(echo "$line" | grep -oP '(?<=REF\t).{1}')
            alt=$(echo "$line" | grep -oP '(?<=ALT\t).{1}')
            af=$(echo "$line" | grep -oP '(?<=AF\t)[0-9.]+')
            echo "${samp} ${chrom} ${pos} ${ref} ${alt} ${af}" >> results/collapsed.tsv
        done
done

# Ensure idempotence: if results/ already contains all expected files, exit successfully
if [ -f "results/collapsed.tsv" ] && \
   [[ $(ls results/*.bam 2>/dev/null || true) =~ M117-bl\.bam|M117-ch\.bam|M117C1-bl\.bam|M117C1-ch\.bam ]] && \
   [[ $(ls results/*.bam.bai 2>/dev/null || true) =~ M117-bl\.bam\.bai|M117-ch\.bam\.bai|M117C1-bl\.bam\.bai|M117C1-ch\.bam\.bai ]] && \
   [[ $(ls results/*.vcf.gz 2>/dev/null || true) =~ M117-bl\.vcf\.gz|M117-ch\.vcf\.gz|M117C1-bl\.vcf\.gz|M117C1-ch\.vcf\.gz ]] && \
   [[ $(ls results/*.vcf.gz.tbi 2>/dev/null || true) =~ M117-bl\.vcf\.gz\.tbi|M117-ch\.vcf\.gz\.tbi|M117C1-bl\.vcf\.gz\.tbi|M117C1-ch\.vcf\.gz\.tbi ]]; then
    exit 0
fi

exit 1