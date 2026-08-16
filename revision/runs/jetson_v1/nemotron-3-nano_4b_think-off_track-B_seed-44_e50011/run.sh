#!/usr/bin/env bash
set -euo pipefail

results=$(mktemp -d)
mkdir -p "$results"

for sample in M117-bl M117-ch M117C1-bl M117C1-ch; do
    bam="$results/${sample}.bam"
    bai="$results/${sample}.bam.bai"
    vcf="$results/${sample}.vcf.gz"
    tbi="$results/${sample}.vcf.gz.tbi"

    # FastQC
    fastqc -o "$results" "${data/raw}/${sample}_1.fq.gz" "${data/raw}/${sample}_2.fq.gz"

    # BWA index
    bwa index chrM.fa

    # BWA alignment (paired)
    bwa mem -t 4 chrM.fa "${data/raw}/${sample}_1.fq.gz" "${data/raw}/${sample}_2.fq.gz" > "$bam"
    samtools view -b -f 0x $bam > "$bam.tmp"
    samtools index "$bam.tmp" && mv "$bam.tmp" "$bam"

    # Variant calling with lofreq
    lofreq -t 4 -r chrM.16,569 -o "$results/${sample}.vcf" \
        --input $bam --ref chrM.16,569 --cov 0.02 --min-allele-freq 0.02

    # Compress VCF
    bcftools view -Oz "$results/${sample}.vcf" > "$vcf"
    tabix "$vcf"

    # Collapse variants per sample (using seqkit)
    if [ ! -s "$results/collapsed.${sample}.tsv" ]; then
        seqkit collapse $bam $results/collapsed.${sample}.tsv chrM 0.02 0.02 > /dev/null
    fi

    # Merge collapsed tables
    if [ ! -s "$results/collapsed.tsv" ] || [ "$(wc -l < results/collapsed.tsv)" -eq 1 ]; then
        seqkit collapse $bam $results/collapsed.${sample}.tsv chrM 0.02 0.02 > /dev/null
    fi

    # Merge all collapsed tables into one TSV
    if [ ! -s "$results/collapsed.tsv" ]; then
        seqkit collapse $bam $results/collapsed.tsv chrM 0.02 0.02 > /dev/null
    else
        cat results/collapsed.tsv results/collapsed.${sample}.tsv | tail -n +2 >> results/collapsed.tsv
    fi

done

# Cleanup temporary files
rm -f "$results/*.tmp"
mv results/* results/
rmdir "$results" 2>/dev/null || true