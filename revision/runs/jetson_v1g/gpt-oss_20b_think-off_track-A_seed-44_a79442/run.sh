#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

mkdir -p results

# Reference indexing
if [[ ! -f data/ref/chrM.fa.fai ]]; then
    samtools faidx data/ref/chrM.fa
fi
if [[ ! -f data/ref/chrM.fa.amb ]]; then
    bwa index data/ref/chrM.fa
fi

for sample in "${SAMPLES[@]}"; do
    bam=results/${sample}.bam
    bai=results/${sample}.bam.bai
    vcf_gz_tbi=results/${sample}.vcf.gz.tbi

    if [[ ! -s "$bam" ]]; then
        bwa mem -t $THREADS \
            -R "@RG\\tID:${sample}\\tSM:${sample}\\tLB:${sample}\\tPL:ILLUMINA" \
            data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz |
        samtools sort -@ $THREADS -o "$bam"
    fi

    if [[ ! -s "$bai" ]]; then
        samtools index -@ $THREADS "$bam"
    fi

    if [[ ! -s "$vcf_gz_tbi" ]]; then
        lofreq call-parallel --pp-threads $THREADS --verbose \
            --ref data/ref/chrM.fa --out results/${sample}.vcf \
            --sig --bonf \
            "$bam"
        bcftools view -O z -o results/${sample}.vcf.gz results/${sample}.vcf
        tabix -p vcf results/${sample}.vcf.gz
        rm results/${sample}.vcf
    fi
done

collapsed=results/collapsed.tsv
rebuild=false
if [[ ! -s "$collapsed" ]]; then
    rebuild=true
else
    for sample in "${SAMPLES[@]}"; do
        if [[ results/${sample}.vcf.gz -nt "$collapsed" ]]; then
            rebuild=true
            break
        fi
    done
fi

if $rebuild; then
    rm -f "$collapsed"
    printf "sample\tchrom\tpos\tref\talt\taf\n" > "$collapsed"
    for sample in "${SAMPLES[@]}"; do
        bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" results/${sample}.vcf.gz >> "$collapsed"
    done
fi

exit 0