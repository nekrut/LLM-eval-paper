#!/usr/bin/env bash
set -euo pipefail

mkdir -p results

# Index reference if not already indexed
if [ ! -f data/ref/chrM.fa.bwt ]; then
    bwa index data/ref/chrM.fa
fi

process_sample() {
    local sample=$1
    local r1="data/raw/${sample}_1.fq.gz"
    local r2="data/raw/${sample}_2.fq.gz"
    local base="results/${sample}"

    if [ -f "${base}.bam" ]; then
        return 0
    fi

    bwa mem -t 4 data/ref/chrM.fa "$r1" "$r2" | samtools view -@ 4 -b - > "${base}.bam"
    samtools sort -@ 4 -o "${base}.sorted.bam" "${base}.bam"
    samtools index -@ 4 "${base}.sorted.bam"

    # Generate VCF with lofreq
    lofreq variant -f data/ref/chrM.fa \
        --min-base-quality 20 \
        --min-read-quality 20 \
        --min-alternative-count 2 \
        --min-supporting-strand 1 \
        -i "${base}.sorted.bam" \
        -o "${base}.vcf"

    bgzip -@ 4 "${base}.vcf"
    tabix -p vcf "${base}.vcf.gz"

    # Index TBI
    samtools index -@ 4 "${base}.sorted.bam"

    # Collapse VCF entries per sample into collapsed.tsv (header added once)
    if [ ! -f results/collapsed.tsv ]; then
        echo -e "sample\tchrom\tpos\tref\talt\taf" > results/collapsed.tsv
    fi

    awk -F'\t' 'NR>1 {print "'"$sample"'", $1, $2, $3, $4, $6}' "${base}.vcf.gz" >> results/collapsed.tsv
}

# Process all samples
for sample in M117-bl M117-ch M117C1-bl M117C1-ch; do
    process_sample "$sample"
done

exit 0