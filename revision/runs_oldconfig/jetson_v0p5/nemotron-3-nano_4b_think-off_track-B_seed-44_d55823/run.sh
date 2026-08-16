#!/usr/bin/env bash
set -euo pipefail

results=$(mktemp -d)
mkdir -p "$results"

for sample in M117-bl M117-ch M117C1-bl M117C1-ch; do
    bam="$results/${sample}.bam"
    bai="$results/${sample}.bam.bai"
    vcf_gz="$results/${sample}.vcf.gz"
    tbi="$results/${sample}.vcf.gz.tbi"

    # FastQC (optional, not required for output but in inventory)
    fastqc -o "$results" "data/raw/${sample}_1.${sample//-/_}1.fq.gz" "data/raw/${sample}_2.${sample//-/_}2.fq.gz"

    # BWA index
    bwa index data/ref/chrM.fa

    # Align reads to chrM
    bwa mem -t 4 data/raw/${sample}_1.${sample//-/_}1.fq.gz data/raw/${sample}_2.${sample//-/_}2.fq.gz "$bam"
    samtools view -b -f 0 $bam > "$results/temp.bam"

    # Index temporary BAM
    samtools index "$results/temp.bam" "$bai"

    # Remove temp files
    rm -f "$results/temp.bam"

    # Lofreq variant calling (requires paired reads)
    lofreq -t 4 -r chrM.16,569 -o "$results/${sample}.vcf" \
        -i "$bai" \
        "data/raw/${sample}_1.${sample//-/_}1.fq.gz" "data/raw/${sample}_2.${sample//-/_}2.fq.gz"

    # Compress VCF
    bcftools view -Oz "$results/${sample}.vcf" > "$vcf_gz"
    tabix "$vcf_gz" > "$tbi"

    # Clean up intermediate files
    rm -f "$results/${sample}.vcf"
done

# Collapse results into one TSV
echo "sample\tchrom\tpos\tref\talt\taf" > "$results/collapsed.tsv"

for sample in M117-bl M117-ch M117C1-bl M117C1-ch; do
    vcf="$results/${sample}.vcf.gz"
    tbi="$results/${sample}.vcf.gz.tbi"
    samtools view -h $vcf | tabix -p vcf -T "$tbi" |
        awk 'NR>1 {print $1 "\t$2\t$3\t$4\t$5\t$6}' >> "$results/collapsed.tsv"
done

# Clean up results directory (optional, but keeps it tidy)
rm -rf "$results"