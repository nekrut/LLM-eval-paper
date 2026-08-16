#!/usr/bin/env bash
set -euo pipefail

THREADS=4
REFDIR="data/ref"
RAWDIR="data/raw"
OUTDIR="results"

mkdir -p "$OUTDIR"

# Index reference
if [[ ! -f "$REFDIR/chrM.fa.bwt" ]]; then
    bwa index "$REFDIR/chrM.fa"
fi

SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

# Process each sample
for SAMPLE in "${SAMPLES[@]}"; do
    R1="$RAWDIR/${SAMPLE}_1.fq.gz"
    R2="$RAWDIR/${SAMPLE}_2.fq.gz"
    BAM="$OUTDIR/${SAMPLE}.bam"
    VCF="$OUTDIR/${SAMPLE}.vcf.gz"
    
    # Map reads
    if [[ ! -f "$BAM" ]]; then
        bwa mem -t "$THREADS" "$REFDIR/chrM.fa" "$R1" "$R2" | \
        samtools sort -@ "$THREADS" -o "$BAM" -
    fi
    
    # Index BAM
    if [[ ! -f "$BAM.bai" ]]; then
        samtools index -@ "$THREADS" "$BAM"
    fi
    
    # Call variants
    if [[ ! -f "$VCF" ]]; then
        VCFTEMP="${OUTDIR}/${SAMPLE}.vcf"
        lofreq call --call-indels -f "$REFDIR/chrM.fa" -o "$VCFTEMP" "$BAM"
        bgzip -f "$VCFTEMP"
        tabix -p vcf "$VCF"
    fi
done

# Collapse VCFs
if [[ ! -f "$OUTDIR/collapsed.tsv" ]]; then
    {
        echo -e "sample\tchrom\tpos\tref\talt\taf"
        for SAMPLE in "${SAMPLES[@]}"; do
            VCF="$OUTDIR/${SAMPLE}.vcf.gz"
            zcat "$VCF" | grep -v '^#' | awk -v sample="$SAMPLE" -F'\t' '{
                af = "."
                if ($8 ~ /AF=/) {
                    af = gensub(/.*AF=([^;]+).*/, "\\1", 1, $8)
                }
                printf "%s\t%s\t%s\t%s\t%s\t%s\n", sample, $1, $2, $4, $5, af
            }'
        done
    } > "$OUTDIR/collapsed.tsv"
fi