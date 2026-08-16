#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
REF="data/ref/chrM.fa"
OUTDIR="results"

mkdir -p "$OUTDIR"

# Index reference
if [ ! -f "${REF}.bwt" ]; then
    bwa index "$REF"
fi

if [ ! -f "${REF}.fai" ]; then
    samtools faidx "$REF"
fi

# Mapping
for SAMPLE in "${SAMPLES[@]}"; do
    R1="data/raw/${SAMPLE}_1.fq.gz"
    R2="data/raw/${SAMPLE}_2.fq.gz"
    BAM="${OUTDIR}/${SAMPLE}.bam"
    
    if [ -f "$BAM" ] && [ -f "${BAM}.bai" ]; then
        continue
    fi
    
    bwa mem -t $THREADS "$REF" "$R1" "$R2" | \
        samtools view -b -h | samtools sort -o "$BAM"
    samtools index "$BAM"
done

# Variant calling
for SAMPLE in "${SAMPLES[@]}"; do
    BAM="${OUTDIR}/${SAMPLE}.bam"
    VCF="${OUTDIR}/${SAMPLE}.vcf"
    VCF_GZ="${OUTDIR}/${SAMPLE}.vcf.gz"
    
    if [ -f "$VCF_GZ" ] && [ -f "${VCF_GZ}.tbi" ]; then
        continue
    fi
    
    if [ ! -f "$VCF" ]; then
        lofreq call -f "$REF" -o "$VCF" "$BAM"
    fi
    
    if [ ! -f "$VCF_GZ" ]; then
        bgzip -f "$VCF"
        tabix -p vcf "$VCF_GZ"
    fi
done

# Collapse
TSV="${OUTDIR}/collapsed.tsv"
if [ ! -f "$TSV" ]; then
    echo -e "sample\tchrom\tpos\tref\talt\taf" > "$TSV"
    
    for SAMPLE in "${SAMPLES[@]}"; do
        VCF_GZ="${OUTDIR}/${SAMPLE}.vcf.gz"
        bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "$VCF_GZ" | \
        awk -v s="$SAMPLE" '{print s "\t" $0}' >> "$TSV"
    done
fi