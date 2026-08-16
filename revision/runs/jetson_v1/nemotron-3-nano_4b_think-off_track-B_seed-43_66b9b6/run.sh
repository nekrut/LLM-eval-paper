#!/usr/bin/env bash
set -euo pipefail

results=$(mktemp -d)
mkdir -p "$results"

for sample in M117-bl M117-ch M117C1-bl M117C1-ch; do
    bam="$results/${sample}.bam"
    bai="$results/${sample}.bam.bai"
    vcf_gz="$results/${sample}.vcf.gz"
    tbi="$results/${sample}.vcf.gz.tbi"

    # FastQC
    fastqc -o "$results" "data/raw/${sample}_1.${sample//-/_}2.fq.gz" "data/raw/${sample}_2.${sample//-/_}2.fq.gz"
    
    # BWA index
    bwa index data/ref/chrM.fa

    # BWA alignment (paired)
    bwa mem -t 4 data/ref/chrM.fa "$results/${sample}_1.${sample//-/_}2.fq.gz" "$results/${sample}_2.${sample//-/_}2.fq.gz" > "${bam}.tmp"
    
    # Sort and index BAM
    samtools sort -@ 4 -o "$bam" "${bam}.tmp"
    samtools index "$bam"

    # Variant calling with lofreq (requires SnpSift for filtering)
    snpsift -t 4 -i data/ref/chrM.fa -o results/${sample}_snp.sif -q "data/raw/${sample}_1.${sample//-/_}2.fq.gz" "data/raw/${sample}_2.${sample//-/_}2.fq.gz"
    lofreq -t 4 -i data/ref/chrM.fa -o results/${sample}.vcf.gz -q "${bam}" -s ${results}/${sample}_snp.sif
    
    # Tabix index VCF
    tabix -p vcf "$vcf_gz"

    # Collapse variant table (using seqkit)
    seqkit collapse -t 4 results/${sample}.vcf.gz > results/collapsed.tsv

done

# Move results to final location and clean up temp files
mv results/* $results/
rmdir results

# Ensure collapsed.tsv has header and correct columns
seqkit format -h results/collapsed.tsv > results/collapsed.tsv
rm results/collapsed.tsv.tmp 2>/dev/null || true