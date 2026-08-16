#!/usr/bin/env bash
set -euo pipefail

samples=()
for f in data/raw/*_1.fq.gz; do
    sample=$(basename "$f" _1.fq.gz)
    samples+=("$sample")
done

if [[ -s results/collapsed.tsv ]]; then
    exit 0
fi

mkdir -p results

THREADS=4

for sample in "${samples[@]}"; do
    fastq1="data/raw/${sample}_1.fq.gz"
    fastq2="data/raw/${sample}_2.fq.gz"
    bam="results/${sample}.bam"
    bai="${bam}.bai"

    if [[ -s "$bam" && -s "$bai" ]]; then
        continue
    fi

    bwa mem -t "$THREADS" data/ref/chrM.fa "$fastq1" "$fastq2" |
        samtools view -@ 4 -b - > "$bam"

    samtools index "$bam"

    lofreq call -f data/ref/chrM.fa -o "results/${sample}.vcf" "$bam"
    bgzip -c "results/${sample}.vcf" > "results/${sample}.vcf.gz"
    tabix -p vcf "results/${sample}.vcf.gz"
done

output_file="results/collapsed.tsv"
echo -e "sample\tchrom\tpos\tref\talt\taf" > "$output_file"

for sample in "${samples[@]}"; do
    vcf_gz="results/${sample}.vcf.gz"
    bcftools query -f '%CHROM\t%POS\t%REF\t%ALT[\t%AF]\n' "$vcf_gz" |
        awk -v s="$sample" '{print s "\t" $0}' >> "$output_file"
done