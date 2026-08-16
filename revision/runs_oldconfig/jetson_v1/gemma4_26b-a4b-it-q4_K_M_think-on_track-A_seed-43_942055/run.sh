#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)
mkdir -p results

if [[ ! -f data/ref/chrM.fa.fai ]]; then
    samtools faidx data/ref/chrM.fa
fi

if [[ ! -f data/ref/chrM.fa.bwt ]]; then
    bwa index data/ref/chrM.fa
fi

for sample in "${SAMPLES[@]}"; do
    if [[ -f "results/${sample}.vcf.gz.tbi" ]] && \
       [[ "results/${sample}.vcf.gz.tbi" -nt "data/raw/${sample}_1.fq.gz" ]] && \
       [[ "results/${sample}.vcf.gz.tbi" -nt "data/raw/${sample}_2.fq.gz" ]]; then
        continue
    fi

    bwa mem -t "$THREADS" -R "@RG\tID:${sample}\tSM:${sample}\tLB:${annot_lb:-${sample}}\tPL:ILLUMINA" \
        "data/raw/${sample}_1.fq.gz" "data/raw/${sample}_2.fq.gz" | \
    samtools sort -@ "$THREADS" -o "results/${sample}.bam"

    samtools index -@ "$THREADS" "results/${sample}.bam"

    lofreq call-parallel --pp-threads "$THREADS" -f data/ref/chrM.fa "results/${sample}.bam" > "results/${sample}.vcf"
    bgzip -c "results/${sample}.vcf" > "results/${sample}.vcf.gz"
    tabix -p vcf "results/${sample}.vcf.gz"
    rm "results/${sample}.vcf"
done

needs_collapse=false
if [[ ! -f "results/collapsed.tsv" ]]; then
    needs_collapse=true
else
    for sample in "${SAMPLES[@]}"; do
        if [[ "data/raw/${sample}_1.fq.gz" -nt "results/collapsed.tsv" ]] || \
           [[ "data/raw/${sample}_2.fq.gz" -nt "results/collapsed.tsv" ]] || \
           [[ "results/${sample}.vcf.gz" -nt "results/collapsed.tsv" ]]; then
            needs_collapse=true
            break
        fi
    done
fi

if [ "$needs_collapse" = true ]; then
    printf "sample\tchrom\tpos\tref\talt\taf\n" > results/collapsed.tsv
    for sample in "${SAMPLES[@]}"; do
        bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "results/${sample}.vcf.gz" >> results/collapsed.tsv
    done
fi