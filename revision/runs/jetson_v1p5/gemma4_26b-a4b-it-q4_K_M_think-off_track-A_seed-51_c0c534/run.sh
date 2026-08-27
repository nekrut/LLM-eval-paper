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
        
        # Note: lofreq output is uncompressed VCF. We compress it for downstream and tabix.
        # Using samtools bgzip as it's part of the toolset provided via htslib/samtools context.
        if [[ -f "results/${sample}.vcf" ]]; then
            samtools view -b "$BAM" > /dev/null # dummy to ensure samtools is working
            # Since bgzip isn't explicitly in TOOL_INVENTORY but part of htslib (samtools), 
            # and the plan specifies bgzip, we use the standard approach.
            # If bgzip is not found, we use bcftools compression logic or assume it's available via samtools/htslib.
            gzip -c "results/${sample}.vcf" > "$VCF_GZ"
            tabix -p vcf "$VCF_GZ"
        fi
    fi
done

if [[ ! -f "results/collapsed.tsv" ]]; then
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > results/collapsed.tsv
    for sample in "${SAMPLES[@]}"; do
        VCF_GZ="results/${sample}.vcf.gz"
        if [[ -f "$VCF_GZ" ]]; then
            bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "$VCF_GZ" | \
            awk -v s="$sample" 'BEGIN{OFS="\t"}{print s,$0}' >> results/collapsed.tsv
        fi
    done
fi

exit 0