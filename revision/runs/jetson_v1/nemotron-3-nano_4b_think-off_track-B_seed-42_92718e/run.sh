#!/usr/bin/env bash
set -euo pipefail
results=$(pwd)/results
mkdir -p "$results"
for sample in M117-bl M117-ch M117C1-bl M117C1-ch; do
    if [[ ! -f "data/raw/${sample}_1.fq.gz" && ! -f "data/raw/${sample}_2.fq.gz" ]]; then
        continue
    fi
    bwa mem data/ref/chrM.fa data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz > "$results/${sample}.bam"
    samtools index "$results/${sample}.bam" 2>/dev/null || true
    bcftools view -f 0x3 $results/${sample}.bam | bcftools norm -mv $results/${sample}.vcf.gz
    tabix -p vcf $results/${sample}.vcf.gz > /dev/null 2>&1
done
snpSift --input $results/*.vcf.gz --output results/collapsed.tsv --format TSV --collapse --threads 4
seqkit merge-tsv results/collapsed.tsv -o results/collapsed.tsv
rm -rf results/*_bam results/*_bai results/*_vcf.gz results/*_vcf.gz.tbi
snpSift --input $results/*.vcf.gz --output results/collapsed.tsv --format TSV --collapse --threads 4
seqkit merge-tsv results/collapsed.tsv -o results/collapsed.tsv