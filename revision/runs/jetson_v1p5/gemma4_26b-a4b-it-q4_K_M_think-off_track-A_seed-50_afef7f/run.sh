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
        
        # Check if bgzip is available via samtools/htslib or use bcftools to compress
        if command -v bgzip >/dev/null 2>&1; then
            bgzip -f "results/${sample}.vcf"
        else
            bcftools view "results/${sample}.vcf" -Oz -o "results/${sample}.vcf.gz"
            rm "results/${sample}.vcf"
        fi

        if [[ ! -f "${VCF_GZ}.tbi" ]]; then
            tabix -p vcf "$VCF_GZ"
        fi
    fi
done

# Create collapsed table if not exists or if we need to rebuild it from current files
printf 'sample\tchrom\tpos\tref\talt\taf\n' > results/collapsed.tsv
for sample in "${SAMPLES[@]}"; do
    VCF_GZ="results/${sample}.vcf.gz"
    if [[ -f "$VCF_GZ" ]]; then
        bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "$VCF_GZ" | \
        awk -v s="$sample" 'BEGIN{OFS="\t"}{print s,$0}' >> results/collapsed.tsv
    fi
done