#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
REF="data/ref/chrM.fa"
mkdir -p results

# Reference indexing with BWA
if [ ! -f "${REF}.amb" ] || [ ! -f "${REF}.ann" ] || [ ! -f "${REF}.bwt" ] || [ ! -f "${REF}.pac" ] || [ ! -f "${REF}.sa" ]; then
    bwa index "$REF"
fi

# Reference indexing with samtools faidx
if [ ! -f "${REF}.fai" ]; then
    samtools faidx "$REF"
fi

for sample in "${SAMPLES[@]}"; do
    BAM="results/${sample}.bam"
    BAI="results/${sample}.bam.bai"
    VCF="results/${sample}.vcf"
    VCFZ="results/${sample}.vcf.gz"
    TBI="results/${sample}.vcf.gz.tbi"

    # Skip sample if all outputs exist
    if [ -f "$BAM" ] && [ -f "$BAI" ] && [ -f "$VCFZ" ] && [ -f "$TBI" ]; then
        continue
    fi

    # Alignment and sorting
    if [ ! -f "$BAM" ]; then
        bwa mem -t "$THREADS" -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
            "$REF" "data/raw/${sample}_1.fq.gz" "data/raw/${sample}_2.fq.gz" |
        samtools sort -@ "$THREADS" -o "$BAM" -
    fi

    # Index BAM
    if [ ! -f "$BAI" ]; then
        samtools index -@ "$THREADS" "$BAM"
    fi

    # Variant calling with LoFreq and compression
    if [ ! -f "$VCFZ" ] || [ ! -f "$TBI" ]; then
        lofreq call-parallel --pp-threads "$THREADS" -f "$REF" -o "$VCF" "$BAM"
        bcftools view -Oz -o "$VCFZ" "$VCF"
        tabix -p vcf "$VCFZ"
    fi
done

# Generate collapsed TSV if not present
COLLAPSED="results/collapsed.tsv"
if [ ! -f "$COLLAPSED" ]; then
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$COLLAPSED"
    for sample in "${SAMPLES[@]}"; do
        VCFZ="results/${sample}.vcf.gz"
        if [ -f "$VCFZ" ]; then
            bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "$VCFZ" |
                awk -v s="$sample" 'BEGIN{OFS="\t"}{print s,$0}' >> "$COLLAPSED"
        fi
    done
fi

exit 0