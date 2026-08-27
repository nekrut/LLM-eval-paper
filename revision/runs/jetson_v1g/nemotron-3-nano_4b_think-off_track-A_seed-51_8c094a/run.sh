#!/usr/bin/env bash
set -euo pipefail
THREADS=4
SAMPLES="M117-bl M117-ch M117C1-bl M117C1-ch"
mkdir -p results
for sample in $SAMPLES; do
    if [[ ! -f "results/${sample}.vcf.gz.tbi" ]] || [[ "results/${sample}.vcf.gz.tbi" -nt "data/raw/${sample}_1.fq.gz" "data/raw/${sample}_2.fq.gz" ]]; then
        bwa mem -t $THREADS data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz | samtools sort -@ $THREADS -o results/${sample}.bam
        samtools index -@ $THREADS results/${sample}.bam
        lofreq call-parallel --pp-threads 4 --verbose \
            --ref data/ref/chrM.fa --out results/${sample}.vcf \
            --sig --bonf results/${sample}.bam
        bgzip -c results/${sample}.vcf > results/${sample}.vcf.gz
        tabix -p vcf results/${sample}.vcf.gz > results/${sample}.vcf.gz.tbi
        rm results/${sample}.vcf
    fi
done
for sample in $SAMPLES; do
    if [[ ! -f "results/collapsed.tsv" ]] || [[ "results/collapsed.tsv" -nt "results/${sample}.vcf.gz" ]]; then
        bcftools query -f '{sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' results/${sample}.vcf.gz | tee -a results/collapsed.tsv
    fi
done
results/collapsed.tsv
```