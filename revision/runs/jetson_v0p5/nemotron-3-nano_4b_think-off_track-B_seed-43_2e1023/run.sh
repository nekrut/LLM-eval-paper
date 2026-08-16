#!/usr/bin/env bash
set -euo pipefail

results=$(mktemp -d)
mkdir -p "$results"

for sample in M117-bl M117-ch M117C1-bl M117C1-ch; do
    bam="$results/${sample}.bam"
    bai="$results/${sample}.bam.bai"
    vcf="$results/${sample}.vcf.gz"

    # FastQC (no output needed, just quality check)
    fastqc -o "$results" "data/raw/${sample}_1.fq.gz" "data/raw/${sample}_2.fq.gz"

    # BWA index
    bwa index data/ref/chrM.fa

    # BWA alignment (paired-end)
    bwa mem -t 4 data/ref/chrM.fa "$results/${sample}_1.fq.gz" "$results/${sample}_2.fq.gz" > "$bam"

    samtools view -b -f 0x $bam | samtools sort -o "$bam" && \
    samtools index "$bam" > "$bai"

    # Lofreq variant calling
    lofreq -t 4 -r chrM:16,569 -i "$bam" -o "$results/${sample}_lofreq.vcf" -q 0.05

    bcftools view -Oz -o "$vcf" "$results/${sample}_lofreq.vcf"

    tabix -p vcf "$vcf.tbi"
done

# Collapse results into one TSV
echo "sample\tchrom\tpos\tref\talt\taf" > "$results/collapsed.tsv"
for sample in M117-bl M117-ch M117C1-bl M117C1-ch; do
    vcf="$results/${sample}.vcf.gz.tbi"
    bcf="${sample}_lofreq.vcf"
    awk -F'\t' 'NR==1 {next} {print $1 "\tchrM\t"$3 "\t"$4 "\t"$5 "\t"NF-2}' "$bcf" >> "$results/collapsed.tsv"
done

# Clean up temporary files
rm -rf "$results"/*.fastqc "$results"/*.vcf.tbi "$results"/*.lofreq.vcf "$results"/*.bai "$results"/*.bam "$results"/*.lofreq.vcf.tmp "$results"/*.tmp "$results"/.bcf

# Ensure results directory is clean
rm -rf "$results"/* 2>/dev/null || true