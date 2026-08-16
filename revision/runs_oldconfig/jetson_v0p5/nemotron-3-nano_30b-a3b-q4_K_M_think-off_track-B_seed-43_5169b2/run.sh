#!/usr/bin/env bash
set -euo pipefail

mkdir -p results

# Index reference if not already indexed
if [ ! -f data/ref/chrM.fa.bwt ]; then
    bwa index data/ref/chrM.fa
fi

# Process each sample
for sample_dir in data/raw/*; do
    base=$(basename "$sample_dir")
    sample="${base%_*}"

    # Skip if results already exist for this sample
    if [ -f "results/${sample}.bam" ]; then
        continue
    fi

    r1="$sample_dir/${base}_1.fq.gz"
    r2="$sample_dir/${base}_2.fq.gz"

    bwa mem -t 4 data/ref/chrM.fa "$r1" "$r2" | samtools view -@ 4 -b - > "results/${sample}.bam"
    samtools sort -@ 4 -o "results/${sample}.sorted.bam" "results/${sample}.bam"
    samtools index "results/${sample}.sorted.bam"

    # lofreq depth calculation
    lofreq depth --mincov 10 --no-indel-plots \
        --output results/"${sample}".lofreq.depth.txt \
        data/ref/chrM.fa \
        <(samtools view -@ 4 "results/${sample}.sorted.bam")

    # Variant calling with lofreq
    lofreq call --mincov 10 --no-indel-plots \
        --output results/"${sample}".lofreq.vcf.gz \
        data/ref/chrM.fa \
        <(samtools view -@ 4 "results/${sample}.sorted.bam") \
        results/"${sample}".lofreq.depth.txt

    # Index VCF
    bgzip -@ 4 "results/${sample}.vcf.gz"
    tabix -p vcf "results/${sample}.vcf.gz.tbi"

    # Extract fields and collapse into final table
    awk 'BEGIN{FS="\t"; OFS="\t"} NR==1{next} {print $8, $1, $2, $4, $5, $7}' \
        <(zcat "results/${sample}.vcf.gz") >> results/collapsed.tsv
done

# Add header to collapsed.tsv if not already present
if [ ! -s results/collapsed.tsv ]; then
    echo -e "sample\tchrom\tpos\tref\talt\taf" > results/collapsed.tsv
fi

# Sort and deduplicate final table (preserve order of first appearance)
awk '!seen[$0]++' results/collapsed.tsv | sort -t$'\t' -k1,1 -k2,2n > results/collapsed.tsv.tmp && mv results/collapsed.tsv.tmp results/collapsed.tsv

exit 0