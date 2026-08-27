#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
REF="data/ref/chrM.fa"

mkdir -p results

if [[ ! -f "${REF}.bwt" ]]; then
    bwa index "$REF"
fi

if [[ ! -f "${REF}.fai" ]]; then
    samtools faidx "$REF"
fi

for sample in "${SAMPLES[@]}"; do
    BAM="results/${sample}.bam"
    VCF_GZ="results/${sample}.vcf.gz"

    if [[ ! -f "$BAM" ]]; then
        bwa mem -t "$THREADS" -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" "$REF" "data/raw/${sample}_1.fq.gz" "data/raw/${sample}_2.fq.gz" | \
        samtools sort -@ "$THREADS" -o "$BAM" -
    fi

    if [[ ! -f "${BAM}.bai" ]]; then
        samtools index -@ "$THREADS" "$BAM"
    fi

    if [[ ! -f "$VCF_GZ" ]]; then
        lofreq call-parallel --pp-threads "$THREADS" -f "$REF" -o "results/${sample}.vcf" "$BAM"
        
        # Note: lofreq output is uncompressed VCF. We compress it to meet requirements.
        # Using samtools bgzip as it is part of the toolset provided via htslib/samtools.
        if [[ -f "results/${sample}.vcf" ]]; then
            bgzip -f "results/${sample}.vcf"
        fi
    fi
done

# Create collapsed table
printf 'sample\tchrom\tpos\tref\talt\taf\n' > results/collapsed.tsv
for sample in "${SAMPLES[@]}"; do
    VCF_GZ="results/${sample}.vcf.gz"
    if [[ -f "$VCF_GZ" ]]; then
        bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "$VCF_GZ" | \
        awk -v s="$sample" 'BEGIN{OFS="\t"}{print s,$0}' >> results/collapsed.tsv
    fi
done