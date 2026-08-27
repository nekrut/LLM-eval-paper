#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

REF="data/ref/GRCh38_chrM/rCRS.fa"

mkdir -p results

# Reference indexing with bwa
if [[ ! -f "${REF}.bwt" ]]; then
    bwa index "$REF"
fi

# Reference indexing with samtools faidx
if [[ ! -f "${REF}.fai" ]]; then
    samtools faidx "$REF"
fi

for sample in "${SAMPLES[@]}"; do
    bam="results/${sample}.bam"

    # Alignment and sort
    if [[ ! -f "$bam" ]]; then
        bwa mem -t "$THREADS" -R "@RG\\tID:${sample}\\tSM:${sample}\\tLB:${sample}\\tPL:ILLUMINA" \
            "$REF" "data/raw/${sample}_1.fq.gz" "data/raw/${sample}_2.fq.gz" | \
        samtools sort -@ "$THREADS" -o "$bam" -
    fi

    # BAM index
    bai="results/${sample}.bam.bai"
    if [[ ! -f "$bai" ]]; then
        samtools index -@ "$THREADS" "$bam"
    fi

    # Variant calling with LoFreq
    vcf="results/${sample}.vcf"
    vcf_gz="${vcf}.gz"
    if [[ ! -f "$vcf" && ! -f "$vcf_gz" ]]; then
        lofreq call-parallel --pp-threads "$THREADS" -f "$REF" -o "$vcf" "$bam"
    fi

    # VCF compression and tabix index
    tbi="results/${sample}.vcf.gz.tbi"
    if [[ ! -f "$tbi" ]]; then
        bgzip -f "$vcf"
        tabix -p vcf "$vcf_gz"
    fi
done

# Collapsed TSV
printf 'sample\tchrom\tpos\tref\talt\taf\n' > results/collapsed.tsv
for sample in "${SAMPLES[@]}"; do
    bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "results/${sample}.vcf.gz" | \
        awk -v s="$sample" 'BEGIN{OFS="\t"}{print s,$0}' >> results/collapsed.tsv
done