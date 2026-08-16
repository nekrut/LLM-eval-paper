#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)

mkdir -p results

REF="data/ref/chrM.fa"
if [ ! -f "${REF}.fai" ]; then
    samtools faidx "$REF"
fi
if [ ! -f "${REF}.amb" ]; then
    bwa index "$REF"
fi

for sample in "${SAMPLES[@]}"; do
    BAM="results/${sample}.bam"
    BAI="results/${sample}.bam.bai"
    VCF_GZ="results/${sample}.vcf.gz"
    TBI="results/${sample}.vcf.gz.tbi"

    if [ -f "$BAM" ] && [ -f "$BAI" ] && [ -f "$VCF_GZ" ] && [ -f "$TBI" ]; then
        continue
    fi

    if [ ! -f "$BAM" ]; then
        bwa mem -t "$THREADS" \
            -R "@RG\\tID:${sample}\\tSM:${sample}\\tLB:${sample}\\tPL:ILLUMINA" \
            data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz |
            samtools sort -@ "$THREADS" -o "$BAM"
    fi

    if [ ! -f "$BAI" ]; then
        samtools index -@ "$THREADS" "$BAM"
    fi

    VCF="results/${sample}.vcf"
    if [ ! -f "$VCF_GZ" ] || [ ! -f "$TBI" ]; then
        lofreq call-parallel --pp-threads "$THREADS" --verbose \
            --ref "$REF" --out "$VCF" \
            --sig --bonf \
            "$BAM"
        bcftools view -O z -o "$VCF_GZ" "$VCF"
        tabix -p vcf "$VCF_GZ"
        rm -f "$VCF"
    fi
done

COLLAPSED="results/collapsed.tsv"
REBUILD=0
for sample in "${SAMPLES[@]}"; do
    VCF_GZ="results/${sample}.vcf.gz"
    if [ ! -f "$COLLAPSED" ] || [ "$(stat -c %Y "$VCF_GZ")" -gt "$(stat -c %Y "$COLLAPSED")" ]; then
        REBUILD=1
        break
    fi
done

if [ "$REBUILD" -eq 1 ]; then
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$COLLAPSED"
    for sample in "${SAMPLES[@]}"; do
        VCF_GZ="results/${sample}.vcf.gz"
        bcftools query -f "${sample}\\t%CHROM\\t%POS\\t%REF\\t%ALT\\t%INFO/AF\n" "$VCF_GZ" >> "$COLLAPSED"
    done
fi

exit 0