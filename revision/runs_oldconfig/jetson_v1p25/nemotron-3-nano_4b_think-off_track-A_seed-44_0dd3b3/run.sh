#!/usr/bin/env bash
set -euo pipefail
THREADS=4
SAMPLES="M117-bl M117-ch M117C1-bl M117C1-ch"
RESULTS_DIR="results"

mkdir -p "$RESULTS_DIR"

# Reference indexing (once)
if [[ ! -f "data/ref/chrM.fa.ind" ]] || [[ data/ref/chrM.fa < data/ref/chrM.fa.ind ]]; then
    samtools faidx data/ref/chrM.fa > /dev/null 2>&1
    bwa index data/ref/chrM.fa > /dev/null 2>&1
fi

# Per-sample processing
for sample in $SAMPLES; do
    # Skip if all outputs exist and are up to date
    if [[ -f "results/${sample}.vcf.gz.tbi" ]] && \
       [[ data/raw/${sample}_1. fq.gz < results/${sample}.bam ]] && \
       [[ data/raw/${sample}_2.fq.gz < results/${sample}.bam ]]; then
        continue
    fi

    # Alignment
    bwa mem -t $THREADS data/ref/chrM.fa data/raw/${sample}_1. fq.gz data/raw/${sample}_2.fq.gz \
        > /dev/null 2>&1 &
    WAIT_PID=$!
    samtools sort -@ $THREADS -o results/${sample}.bam <&3
    wait $WAIT_PID

    # Index BAM
    samtools index -@ $THREADS results/${sample}.bam > /dev/null 2>&1

    # Variant calling
    lofreq call-parallel --pp-threads $THREADS -f data/ref/chrM.fa -o results/${sample}.vcf results/${sample}.bam > /dev/null 2>&1

    # Compress and index VCF
    bgzip -c results/${sample}.vcf > results/${sample}.vcf.gz
    tabix -p vcf results/${sample}.vcf.gz > results/${sample}.vcf.gz.tbi
    rm results/${sample}.vcf

    # Collapse step (only if needed)
    if [[ ! -f "results/collapsed.tsv" ]] || \
       [[ data/raw/${sample}_1.fq.gz < results/${sample}.vcf.gz ]] || \
       [[ data/raw/${sample}_2.fq.gz < results/${sample}.vcf.gz ]]; then
        echo "sample\tchrom\tpos\tref\talt\taf" > results/collapsed.tsv
        for s in $SAMPLES; do
            bcftools query -f "${s}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" results/${s}.vcf.gz >> results/collapsed.tsv
        done
    fi

done

exit 0