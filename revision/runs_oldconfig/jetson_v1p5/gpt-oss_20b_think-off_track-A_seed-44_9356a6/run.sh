#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

# Exit if all expected outputs already exist
ALL_EXIST=true
for sample in "${SAMPLES[@]}"; do
    for ext in bam bai vcf.gz tbi; do
        file="results/${sample}.${ext}"
        if [[ ! -f "$file" ]]; then
            ALL_EXIST=false
            break 2
        fi
    done
done
if [[ $ALL_EXIST == true && -f results/collapsed.tsv ]]; then
    exit 0
fi

mkdir -p results

# Reference indexing
if [[ ! -f data/ref/chrM.fa.bwt ]]; then
    bwa index data/ref/chrM.fa
fi
if [[ ! -f data/ref/chrM.fa.fai ]]; then
    samtools faidx data/ref/chrM.fa
fi

for sample in "${SAMPLES[@]}"; do
    bam="results/${sample}.bam"
    bai="results/${sample}.bam.bai"
    vcf="results/${sample}.vcf"
    vcfz="results/${sample}.vcf.gz"
    tbi="results/${sample}.tbi"

    if [[ ! -f "$bam" ]]; then
        bwa mem -t "$THREADS" \
            -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
            data/ref/chrM.fa \
            data/raw/${sample}_1.fq.gz \
            data/raw/${sample}_2.fq.gz | \
        samtools sort -@ "$THREADS" -o "$bam" -
    fi

    if [[ ! -f "$bai" ]]; then
        samtools index -@ "$THREADS" "$bam"
    fi

    if [[ ! -f "$vcfz" ]]; then
        lofreq call-parallel --pp-threads "$THREADS" \
            -f data/ref/chrM.fa \
            -o "$vcf" \
            "$bam"

        bcftools view -O z -o "$vcfz" "$vcf"
        tabix -p vcf "$vcfz"
    else
        if [[ ! -f "$tbi" ]]; then
            tabix -p vcf "$vcfz"
        fi
    fi
done

if [[ ! -f results/collapsed.tsv ]]; then
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > results/collapsed.tsv
    for sample in "${SAMPLES[@]}"; do
        vcfz="results/${sample}.vcf.gz"
        if [[ -f "$vcfz" ]]; then
            bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "$vcfz" | \
                awk -v s="$sample" 'BEGIN{OFS="\t"}{print s,$0}' >> results/collapsed.tsv
        fi
    done
fi

exit 0