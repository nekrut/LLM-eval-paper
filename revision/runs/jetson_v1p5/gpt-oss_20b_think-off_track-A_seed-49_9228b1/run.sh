#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

mkdir -p results

# Reference indexing
if [ ! -f data/ref/chrM.fa.bwt ]; then
    bwa index data/ref/chrM.fa
fi
if [ ! -f data/ref/chrM.fa.fai ]; then
    samtools faidx data/ref/chrM.fa
fi

for sample in "${SAMPLES[@]}"; do
    bam=results/${sample}.bam
    bai=results/${sample}.bam.bai
    vcf=results/${sample}.vcf
    vcfz=results/${sample}.vcf.gz

    # Alignment and sort
    if [ ! -f "$bam" ]; then
        bwa mem -t $THREADS -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" data/ref/chrM.fa data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz | samtools sort -@ $THREADS -o "$bam" -
    fi

    # BAM index
    if [ ! -f "$bai" ]; then
        samtools index -@ $THREADS "$bam"
    fi

    # Variant calling
    if [ ! -f "$vcfz" ]; then
        lofreq call-parallel --pp-threads $THREADS -f data/ref/chrM.fa -o "$vcf" "$bam"
        bcftools view -Oz -o "$vcfz" "$vcf"
        tabix -p vcf "$vcfz"
        rm -f "$vcf"
    fi
done

# Collapsed TSV
collapsed=results/collapsed.tsv
printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed"
for sample in "${SAMPLES[@]}"; do
    vcfz=results/${sample}.vcf.gz
    if [ -f "$vcfz" ]; then
        bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "$vcfz" | awk -v s="$sample" 'BEGIN{OFS="\t"}{print s,$0}' >> "$collapsed"
    fi
done

exit 0