#!/usr/bin/env bash
set -euo pipefail
results=$(pwd)/results
mkdir -p "$results"
for sample in M117-bl M117-ch M117C1-bl M117C1-ch; do
    bam="$results/${sample}.bam"
    bai="$results/${sample}.bam.bai"
    vcf="$results/${sample}.vcf.gz"
    tbi="$results/${sample}.vcf.gz.tbi"
    if [ ! -f "$bam" ] || [ ! -f "$bai" ]; then
        bwa mem data/ref/chrM.fa data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz > $bam
        samtools view -b -F 0x36 $bam > $bam
        samtools index $bam $bai
    fi
    if [ ! -f "$vcf" ] || [ ! -f "$tbi" ]; then
        bcftools call -M -m vcf -o $vcf data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz > /dev/null 2>&1 | lofreq -r chrM.bed -o $vcf
        tabix -p vcf $tbi
    fi
done
echo "sample\tchrom\tpos\tref\talt\taf" > "$results/collapsed.tsv"
for sample in M117-bl M117-ch M117C1-bl M117C1-ch; do
    bam="$results/${sample}.bam"
    vcf="$results/${sample}.vcf.gz"
    awk -F'\t' 'NR>2 {print $1 "\t" $2 "\t" $3 "\t" $4 "\t" $5}' "$vcf" | lofreq -r chrM.bed -o results/collapsed.tsv
done