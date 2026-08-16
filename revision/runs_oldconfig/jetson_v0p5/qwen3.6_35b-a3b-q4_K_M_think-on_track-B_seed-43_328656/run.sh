#!/usr/bin/env bash
set -euo pipefail

REF="data/ref/chrM.fa"
RAW_DIR="data/raw"
RES_DIR="results"
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)

mkdir -p "$RES_DIR"

# Index reference if not already done
if [[ ! -f "${REF}.fai" || ! -f "${REF}.amb" ]]; then
    samtools faidx "$REF"
    bwa index "$REF"
fi

for samp in "${SAMPLES[@]}"; do
    bam="$RES_DIR/${samp}.bam"
    bai="${bam}.bai"
    vcf_gz="$RES_DIR/${samp}.vcf.gz"
    tbi="${vcf_gz}.tbi"

    # Skip if all expected outputs exist
    [[ -f "$bam" && -f "$bai" && -f "$vcf_gz" && -f "$tbi" ]] && continue

    # Alignment & BAM processing
    if [[ ! -f "$bai" ]]; then
        bwa mem -t 4 "$REF" "$RAW_DIR/${samp}_1.fq.gz" "$RAW_DIR/${samp}_2.fq.gz" \
            | samtools sort -@ 4 -o "$bam" -
        samtools index "$bam"
    fi

    # Variant calling & VCF compression/indexing
    if [[ ! -f "$tbi" ]]; then
        vcf="$RES_DIR/${samp}.vcf"
        lofreq call -f "$REF" -o "$vcf" "$bam"
        bcftools view -Oz -o "$vcf_gz" "$vcf"
        bcftools index -t "$vcf_gz"
        rm -f "$vcf"
    fi
done

# Collapse to TSV
collapsed="$RES_DIR/collapsed.tsv"
if [[ ! -f "$collapsed" ]]; then
    printf "sample\tchrom\tpos\tref\talt\taf\n" > "$collapsed"
    for samp in "${SAMPLES[@]}"; do
        vcf_gz="$RES_DIR/${samp}.vcf.gz"
        if [[ -f "$vcf_gz" ]]; then
            bcftools query -f "%CHROM\t%POS\t%REF\t%ALT\t%AF\n" "$vcf_gz" \
                | awk -v s="$samp" '{print s"\t"$0}' >> "$collapsed"
        fi
    done
fi