#!/usr/bin/env bash
set -euo pipefail

# Ensure results directory exists (idempotent)
mkdir -p results

# Define sample list and fastq files
samples=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
ref="data/ref/chrM.fa"

# Function to process a single sample
process_sample() {
    local sample=$1
    local r1="data/raw/${sample}_1.fq.gz"
    local r2="data/raw/${sample}_2.fq.gz"
    local base="${sample}"
    
    # Skip if BAM already exists (idempotent)
    [ -f "results/${base}.bam" ] && return 0
    
    # Align with bwa-mem
    bwa mem -t 4 "${ref}" "${r1}" "${r2}" | samtools view -@ 4 -b - > "results/${base}.bam"
    
    # Index BAM
    samtools index "results/${base}.bam"
    
    # Preprocess with lofreq (realign and call variants)
    lofreq preprocess --no-indel-realignment \
        --output-prefix "results/${base}" \
        -t 4 "${ref}" "results/${base}.bam"
    
    # Call variants with lofreq caller
    lofreq caller \
        --min-alternative-reads 2 \
        --min-alt-depth 10 \
        --min-base-quality 13 \
        --min-map-quality 25 \
        -t 4 "${ref}" "results/${base}.bam" > "results/${base}.lofreq.vcf"
    
    # Compress and index VCF with bgzip and tabix
    bgzip "results/${base}.lofreq.vcf"
    tabix -p vcf "results/${base}.lofreq.vcf.gz"
    
    # Rename to expected names
    mv "results/${base}.lofreq.vcf.gz" "results/${base}.vcf.gz"
    mv "results/${base}.lofreq.vcf.gz.tbi" "results/${base}.vcf.gz.tbi"
}

# Process each sample in parallel (max 4 threads total)
for sample in "${samples[@]}"; do
    process_sample "$sample" &
done

wait

# Collapse VCFs into collapsed.tsv using bcftools and awk
bcftools concat -Oz results/*.vcf.gz | tabix -p vcf -
bcftools query -f '%CHROM\t%POS[\t%REF>\t%ALT]\t%AF\n' -samples $(printf "%s " ${samples[@]}) \
    <(bcftools view -h results/*.vcf.gz | grep -E '^##SAMPLE<' | cut -d'=' -f2) \
    | awk -F'\t' 'BEGIN{print "sample\tchrom\tpos\tref\talt\taf"} {for(i=1;i<=NF;i++) printf "%s\t", $i; print ""}' \
    > results/collapsed.tsv

# Fix header and format
awk 'NR==1{for(i=1;i<=6;i++) printf "sample\tchrom\tpos\tref\talt\taf\n"; next} {print}' results/collapsed.tsv > results/collapsed.tsv.tmp && mv results/collapsed.tsv.tmp results/collapsed.tsv

# Ensure collapsed.tsv has correct format
awk 'BEGIN{FS=OFS="\t"} NR==1{print "sample\tchrom\tpos\tref\talt\taf"; next} {printf "%s\t%s\t%d\t%s\t%s\t%f\n", $1, $2, $3, $4, $5, $6}' results/collapsed.tsv > results/collapsed.tsv.tmp && mv results/collapsed.tsv.tmp results/collapsed.tsv

# End of script
exit 0