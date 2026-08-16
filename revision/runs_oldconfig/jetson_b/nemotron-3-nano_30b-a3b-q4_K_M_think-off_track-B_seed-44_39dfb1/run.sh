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

    # Skip if all outputs exist
    [ -f "${base}.bam" ] && [ -f "${base}.bai" ] && [ -f "${base}.vcf.gz" ] && exit 0

    bwa mem -t 4 data/ref/chrM.fa "$r1" "$r2" | samtools view -@ 4 -b - > "${base}.bam"
    samtools sort -o "${base}.sorted.bam" "${base}.bam"
    samtools index -@ 4 "${base}.sorted.bam"

    # Variant calling with lofreq
    lofreq variant -f data/ref/chrM.fa --min-read-depth 8 --min-alternative-count 2 \
        --min-ALT-depth 5 --min-FS 30 --max-FS 1000 \
        --min-BQ 13 --min-MQ 20 --min-MAPQ 30 \
        -o "${base}.vcf.gz" "${base}.sorted.bam"

    tabix -p vcf "${base}.vcf.gz"
}

# Process each sample
for s in M117-bl M117-ch M117C1-bl M117C1-ch; do
    process_sample "$s"
done

# Collapse VCFs into collapsed.tsv
collapsed_tsv="results/collapsed.tsv"
echo -e "sample\tchrom\tpos\tref\talt\taf" > "$collapsed_tsv"

for vcf in results/*.vcf.gz; do
    sample=$(basename "${vcf%.vcf.gz}")
    zcat "$vcf" | \
        awk 'NR==1{next} $0 ~ /^#/ {next} {print $1"\t"$2"\t"$4"\t"$5"\t"$8}' >> "$collapsed_tsv"
done

# Sort and deduplicate collapsed.tsv
sort -k1,1 -k2,2n -k3,3n "$collapsed_tsv" | uniq > "${collapsed_tsv}.sorted"
mv "${collapsed_tsv}.sorted" "$collapsed_tsv"

# Index the final table with tabix for completeness (optional)
tabix -p vcf "$collapsed_tsv" || true

exit 0