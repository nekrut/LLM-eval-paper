#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
RESULTS_DIR="results"
RAW_DIR="data/raw"
REF_DIR="data/ref"
REF_FA="$REF_DIR/chrM.fa"

mkdir -p "$RESULTS_DIR"

# 2. Reference indexing (once)
if [[ ! -f "$REF_FA.fai" ]]; then
    samtools faidx "$REF_FA"
fi
if [[ ! -f "$REF_FA.bwt" ]]; then
    bwa index "$REF_FA"
fi

# 3. Per-sample alignment with bwa mem
for sample in "${SAMPLES[@]}"; do
    _1="$RAW_DIR/${sample}_1.fq.gz"
    _2="$RAW_DIR/${sample}_2.fq.gz"
    bam="$RESULTS_DIR/${sample}.bam"
    bai="$RESULTS_DIR/${sample}.bam.bai"
    vcf="$RESULTS_DIR/${sample}.vcf"
    vcfgz="$RESULTS_DIR/${sample}.vcf.gz"
    vcftbi="$RESULTS_DIR/${sample}.vcf.gz.tbi"

    if [[ -f "$vcftbi" ]]; then
        continue
    fi

    bwa mem -t "$THREADS" -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" "$REF_FA" "$_1" "$_2" | \
    samtools sort -@ "$THREADS" -o "$bam"
    samtools index -@ "$THREADS" "$bam"
    lofreq call-parallel --pp-threads "$THREADS" -f "$REF_FA" -o "$vcf" "$bam"
    bgzip -c "$vcf" > "$vcfgz"
    tabix -p vcf "$vcfgz"
    rm "$vcf"
done

# 8. Collapse step
COLLAPSED="$RESULTS_DIR/collapsed.tsv"
if [[ -f "$COLLAPSED" ]]; then
    # Check if any input VCF is newer than the TSV
    latest_vcf=0
    for sample in "${SAMPLES[@]}"; do
        vcfgz="$RESULTS_DIR/${sample}.vcf.gz"
        if [[ -f "$vcfgz" ]]; then
            if [[ "$vcfgz" -nt "$COLLAPSED" ]]; then
                latest_vcf=1
                break
            fi
        fi
    done
    if [[ "$latest_vcf" -eq 0 ]]; then
        exit 0
    fi
fi

echo -e "sample\tchrom\tpos\tref\talt\taf" > "$COLLAPSED"
for sample in "${SAMPLES[@]}"; do
    vcfgz="$RESULTS_DIR/${sample}.vcf.gz"
    bcftools query -f '{sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "$vcfgz" >> "$COLLAPSED"
done