#!/usr/bin/env bash
set -euo pipefail

RAW="data/raw"
REF="data/ref"
OUT="results"

mkdir -p "$OUT"

# Index reference for BWA and Samtools
if [ ! -f "$REF/chrM.fa.bwt" ]; then
    bwa index "$REF/chrM.fa"
fi
if [ ! -f "$REF/chrM.fa.fai" ]; then
    samtools faidx "$REF/chrM.fa"
fi

# Process each sample
for sample in M117-bl M117-ch M117C1-bl M117C1-ch; do
    # Alignment
    if [ ! -f "$OUT/${sample}.bam" ]; then
        bwa mem -t 4 "$REF/chrM.fa" "$RAW/${sample}_1.fq.gz" "$RAW/${sample}_2.fq.gz" \
            | samtools view -b - \
            | samtools sort -@ 4 -o "$OUT/${sample}.bam" -
        samtools index "$OUT/${sample}.bam"
    fi

    # Variant Calling
    if [ ! -f "$OUT/${sample}.vcf.gz" ]; then
        lofreq call-parallel -f "$REF/chrM.fa" "$OUT/${sample}.bam" -o "$OUT/${sample}.vcf.gz" -m indel -t 4
        tabix -p vcf "$OUT/${sample}.vcf.gz"
    fi
done

# Collapse results
if [ ! -f "$OUT/collapsed.tsv" ]; then
    {
        echo -e "sample\tchrom\tpos\tref\talt\taf"
        for sample in M117-bl M117-ch M117C1-bl M117C1-ch; do
            bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "$OUT/${sample}.vcf.gz" | sed "s/^/$sample\t/"
        done
    } > "$OUT/collapsed.tsv"
fi