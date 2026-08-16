#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES="M117-bl M117-ch M117C1-bl M117C1-ch"

mkdir -p results

# Reference index (once)
if [[ ! -f data/ref/chrM.fa.fai || $(stat -c %Y data/ref/chrM.fa.fai) -lt $(stat -c %Y data/ref/chrM.af 2>/dev/null || echo 0) ]]; then
    samtools faidx data/ref/chrM.fa > /dev/null
    bwa index data/ref/chrM.fa > /dev/null
fi

# Per-sample processing
for s in $SAMPLES; do
    # Align and sort BAM
    if [[ ! -f results/${s}.bam || $(stat -c %Y results/${s}.bam) -lt $(stat -c %Y data/raw/${s}_1.fq.gz 2>/dev/null || echo 0) ]]; then
        bwa mem -t $THREADS -R "@RG\tID:${s}\tSM:${s}\tLB:${s}\tPL:ILLUMINA" \
            data/raw/${s}_1.fq.gz data/raw/${s}_2.fq.gz | samtools sort -@ $THREADS -o results/${s}.bam > /dev/null
    fi

    # Index BAM
    if [[ ! -f results/${s}.bam.bai || $(stat -c %Y results/${s}.bam.bai) -lt $(stat -c %Y results/${s}.bam 2>/dev/null || echo 0) ]]; then
        samtools index -@ $THREADS results/${s}.bam > /dev/null
    fi

    # Variant calling with lofreq
    if [[ ! -f results/${s}.vcf || $(stat -c %Y results/${s}.vcf) -lt $(stat -c %Y results/${s}.bam 2>/dev/null || echo 0) ]]; then
        lofreq call-parallel --pp-threads $THREADS -f data/ref/chrM.fa -o results/${s}.vcf results/${s}.bam > /dev/null
    fi

    # Compress VCF
    if [[ ! -f results/${s}.vcf.gz || $(stat -c %Y results/${s}.vcf.gz) -lt $(stat -c %Y results/${s}.vcf 2>/dev/null || echo 0) ]]; then
        bgzip -c results/${s}.vcf > results/${s}.vcf.gz > /dev/null
    fi

    # Index compressed VCF
    if [[ ! -f results/${s}.vcf.gz.tbi || $(stat -c %Y results/${s}.vcf.gz.tbi) -lt $(stat -c %Y results/${s}.vcf.gz 2>/dev/null || echo 0) ]]; then
        tabix -p vcf results/${s}.vcf.gz > /dev/null
    fi

    # Remove uncompressed VCF (idempotent)
    rm -f results/${s}.vcf
done

# Collapse TSV
if [[ ! -s results/collapsed.tsv ]]; then
    echo "sample\tchrom\tpos\tref\talt\taf" > results/collapsed.tsv
fi

latest_ts=0
for s in $SAMPLES; do
    v="${s}.vcf.gz"
    if [[ -f "$v" ]]; then
        ts=$(stat -c %Y "$v")
        (( ts > latest_ts )) && latest_ts=$ts
    fi
done

if [[ -s results/collapsed.tsv && $(stat -c %Y results/collapsed.tsv) -ge $latest_ts ]]; then
    exit 0
fi

# Rebuild collapsed TSV
tmp=$(mktemp)
echo "sample\tchrom\tpos\tref\talt\taf" > "$tmp"
for s in $SAMPLES; do
    v="${s}.vcf.gz"
    if [[ -f "$v" ]]; then
        bcftools query -f "${s}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "$v" >> "$tmp"
    fi
done
mv "$tmp" results/collapsed.tsv

# Cleanup temp file (should not exist)
rm -f "$tmp"

exit 0