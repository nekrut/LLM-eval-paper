#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)

# Create results directory if it does not exist
mkdir -p results

# Reference indexing (once)
if [ ! -f data/ref/chrM.fa.bwt ]; then
    samtools faidx data/ref/chrM.fa
    bwa index data/ref/chrM.fa
fi

# Per-sample processing
for sample in "${SAMPLES[@]}"; do
    bam=results/${sample}.bam
    bai=results/${sample}.bam.bai
    vcf_gz=results/${sample}.vcf.gz
    tbi=results/${sample}.vcf.gz.tbi

    fq1=data/raw/${sample}_1.fq.gz
    fq2=data/raw/${sample}_2.fq.gz

    # Alignment and sorting
    if [ ! -e "$bam" ] || [ "$bam" -ot "$fq1" ] || [ "$bam" -ot "$fq2" ]; then
        bwa mem -t $THREADS \
            -R "@RG\\tID:${sample}\\tSM:${sample}\\tLB:${sample}\\tPL:ILLUMINA" \
            data/ref/chrM.fa "$fq1" "$fq2" | \
            samtools sort -@ $THREADS -o "$bam"
    fi

    # BAM indexing
    if [ ! -e "$bai" ] || [ "$bai" -ot "$bam" ]; then
        samtools index -@ $THREADS "$bam"
    fi

    # Variant calling
    vcf=results/${sample}.vcf
    if [ ! -e "$tbi" ] || [ "$tbi" -ot "$bam" ]; then
        lofreq call-parallel --pp-threads $THREADS \
            -f data/ref/chrM.fa -b "$bam" > "$vcf"
        bcftools view -O z -o "$vcf_gz" "$vcf"
        tabix -p vcf "$vcf_gz"
        rm -f "$vcf"
    fi
done

# Collapse step
collapsed=results/collapsed.tsv
needs_rebuild=false
for sample in "${SAMPLES[@]}"; do
    vcf_gz=results/${sample}.vcf.gz
    if [ ! -e "$collapsed" ] || [ "$vcf_gz" -ot "$collapsed" ]; then
        needs_rebuild=true
        break
    fi
done

if $needs_rebuild; then
    printf "sample\tchrom\tpos\tref\talt\taf\n" > "$collapsed"
    for sample in "${SAMPLES[@]}"; do
        bcftools query -f "${sample}\\t%CHROM\\t%POS\\t%REF\\t%ALT\\t%INFO/AF\n" \
            results/${sample}.vcf.gz >> "$collapsed"
    done
fi

exit 0