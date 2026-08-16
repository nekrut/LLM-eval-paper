#!/usr/bin/env bash
set -euo pipefail

THREADS=4
samples=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

mkdir -p results

# reference indexing (once)
if [ ! -f data/ref/chrM.fa.fai ]; then
    samtools faidx data/ref/chrM.fa
    bwa index data/ref/chrM.fa
fi

for sample in "${samples[@]}"; do
    if [ -f "results/${sample}.vcf.gz.tbi" ]; then
        continue
    fi

    # alignment
    bwa mem -t 4 \
        -R "@RG\\tID:${sample}\\tSM:${sample}\\tLB:${sample}\\tPL:ILLUMINA" \
        data/ref/chrM.fa \
        data/raw/${sample}_1.fq.gz \
        data/raw/${sample}_2.fq.gz |
    samtools sort -@ 4 -o results/${sample}.bam

    # indexing
    samtools index -@ 4 results/${sample}.bam

    # variant calling
    lofreq call-parallel --pp-threads 4 -f data/ref/chrM.fa -o results/${sample}.vcf results/${sample}.bam

    # compress and index
    bcftools view -O z -o results/${sample}.vcf.gz results/${sample}.vcf
    tabix -p vcf results/${sample}.vcf.gz
done

# collapse step
rebuild=0
if [ ! -f results/collapsed.tsv ]; then
    rebuild=1
else
    for s in "${samples[@]}"; do
        if [ "results/${s}.vcf.gz" -nt "results/collapsed.tsv" ]; then
            rebuild=1; break;
        fi
    done
fi
if [ "$rebuild" -eq 1 ]; then
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > results/collapsed.tsv
    for s in "${samples[@]}"; do
        bcftools query -f '{s}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "results/${s}.vcf.gz" >> results/collapsed.tsv
    done
fi