#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)

mkdir -p results

REF=data/ref/chrM.fa
if [ ! -f "${REF}.fai" ]; then
    samtools faidx "$REF"
fi
if [ ! -f "${REF}.amb" ]; then
    bwa index "$REF"
fi

for sample in "${SAMPLES[@]}"; do
    R1=data/raw/${sample}_1.fq.gz
    R2=data/raw/${sample}_2.fq.gz
    BAM=results/${sample}.bam
    BAI=results/${sample}.bam.bai
    VCF=results/${sample}.vcf
    VCFZ=results/${sample}.vcf.gz

    if [ ! -f "$BAM" ] || [ "$R1" -nt "$BAM" ] || [ "$R2" -nt "$BAM" ]; then
        bwa mem -t "$THREADS" -R "@RG\\tID:${sample}\\tSM:${sample}\\tLB:${sample}\\tPL:ILLUMINA" \
            "$REF" "$R1" "$R2" | samtools sort -@ "$THREADS" -o "$BAM"
    fi

    if [ ! -f "$BAI" ] || [ "$BAM" -nt "$BAI" ]; then
        samtools index -@ "$THREADS" "$BAM"
    fi

    if [ ! -f "$VCFZ" ] || [ "$BAM" -nt "$VCFZ" ]; then
        lofreq call-parallel --pp-threads "$THREADS" -f "$REF" -b "$BAM" > "$VCF"
        bcftools view -O z -o "$VCFZ" "$VCF"
        tabix -p vcf "$VCFZ"
        rm -f "$VCF"
    fi
done

COLLAPSED=results/collapsed.tsv
needs_rebuild=false
if [ ! -f "$COLLAPSED" ]; then
    needs_rebuild=true
else
    for sample in "${SAMPLES[@]}"; do
        VCFZ=results/${sample}.vcf.gz
        if [ "$VCFZ" -nt "$COLLAPSED" ]; then
            needs_rebuild=true
            break
        fi
    done
fi

if $needs_rebuild; then
    {
        echo -e "sample\tchrom\tpos\tref\talt\taf"
        for sample in "${SAMPLES[@]}"; do
            VCFZ=results/${sample}.vcf.gz
            bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "$VCFZ"
        done
    } > "$COLLAPSED"
fi

exit 0