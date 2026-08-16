#!/usr/bin/env bash
set -euo pipefail
THREADS=4
SAMPLES="M117-bl M117-ch M117C1-bl M117C1-ch"
mkdir -p results

# Reference indexing (once)
if [[ ! -f data/ref/chrM.fa.ind ]]; then
    samtools faidx data/ref/chrM.fa
    bwa index data/ref/chrM.fa
fi

for S in $SAMPLES; do
    # Alignment
    if [[ ! -s results/${S}.bam ]] || [[ $(stat -c %Y results/${S}.bam) -lt $(stat -c %Y data/raw/${S}_1.fq.gz) ]] || [[ $(stat -c %Y results/${S}.bam) -lt $(stat -c %Y data/raw/${S}_2.fq.gz) ]]; then
        bwa mem -t $THREADS -R "@RG\tID:${S}\tSM:${S}\tLB:${S}\tPL:ILLUMINA" \
            data/raw/${S}_1.fq.gz data/raw/${S}_2.fq.gz > results/${S}.bam
    fi

    # BAM indexing
    if [[ ! -s results/${S}.bam.ind ]] || [[ $(stat -c %Y results/${S}.bam) -lt $(stat -c %Y results/${S}.bam.ind) ]]; then
        samtools index -@ $THREADS results/${S}.bam
    fi

    # Variant calling
    if [[ ! -s results/${S}.vcf ]] || [[ $(stat -c %Y data/raw/${S}_1.fq.gz) -lt $(stat -c %Y results/${S}.vcf) ]] || [[ $(stat -c %Y data/raw/${S}_2.fq.gz) -lt $(stat -c %Y results/${S}.vcf) ]]; then
        lofreq call-parallel --pp-threads $THREADS -f data/ref/chrM.fa -o results/${S}.vcf results/${S}.bam
    fi

    # Compression and indexing
    if [[ ! -s results/${S}.vcf.gz ]] || [[ $(stat -c %Y results/${S}.vcf) -lt $(stat -c %Y results/${S}.vcf.gz) ]]; then
        bgzip -@ $THREADS results/${S}.vcf > results/${S}.vcf.gz
        tabix -p vcf -@ $THREADS results/${S}.vcf.gz.1 2>/dev/null || true
    fi

    # Remove uncompressed VCF if compressed exists and is newer
    if [[ -s results/${S}.vcf ]] && [[ $(stat -c %Y results/${S}.vcf) -lt $(stat -c %Y results/${S}.vcf.gz) ]]; then
        rm results/${S}.vcf
    fi

    # Collapse step (only if TSV is missing or outdated)
    if [[ ! -s results/collapsed.tsv ]] || [[ $(stat -c %Y data/raw/${S}_1.fq.gz) -lt $(stat -c %Y results/collapsed.tsv) ]] || [[ $(stat -c %Y data/raw/${S}_2.fq.gz) -lt $(stat -c %Y results/collapsed.tsv) ]]; then
        echo "sample\tchrom\tpos\tref\talt\taf" > results/collapsed.tsv
        for S in $SAMPLES; do
            bcftools query -f "${S}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" results/${S}.vcf.gz >> results/collapsed.tsv
        done
    fi
done

exit 0