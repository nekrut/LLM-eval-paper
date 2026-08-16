#!/usr/bin/env bash
set -euo pipefail

mkdir -p results

# Reference indexing
if [ ! -f "data/ref/chrM.fa.bwt" ]; then
    bwa index data/ref/chrM.fa
fi
if [ ! -f "data/tref/chrM.fa.fai" ] && [ ! -f "data/ref/chrM.fa.fai" ]; then
    samtools faidx data/ref/chrM.fa
fi

SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

for s in "${SAMPLES[@]}"; do
    # Alignment and Sorting
    if [ ! -f "results/${s}.bam" ]; then
        bwa mem -t 4 data/ref/chrM.fa \
            "data/raw/${s}_1.fq.gz" \
            "data/raw/${s}_2.fq.gz" | \
        samtools sort -@ 4 -o "results/${s}.bam"
    fi

    if [ ! -f "results/${s}.bam.bai" ]; then
        samtools index "results/${s}.bam"
    fi

    # Variant Calling
    if [ ! -f "results/${s}.vcf.gz" ]; then
        # lofreq call output is often plain text VCF; we compress it to .vcf.gz
        lofreq call -f data/ref/chrM.fa -o "results/${s}.vcf" -p "results/${s}_tmp" "results/${s}.bam" || true
        if [ -f "results/${s}.vcf" ]; then
            bcftools view -Oz -o "results/${s}.vcf.gz" "results/${s}.vcf"
            tabix -p vcf "results/${s}.vcf.gz"
            rm -f "results/${s}.vcf" "results/${s}_tmp"*
        fi
    fi

    if [ ! -f "results/${s}.vcf.gz.tbi" ]; then
        tabix -p vcf "results/${s}.vcf.gz"
    fi
done

# Collapsed Table Generation
if [ ! -f "results/collapsed.tsv" ]; then
    echo -e "sample\tchrom\tpos\tref\talt\taf" > results/collapsed.tsv
    for s in "${SAMPLES[@]}"; do
        if [ -f "results/${s}.vcf.gz" ]; then
            bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%AF\n' "results/${s}.vcf.gz" | \
            awk -v smp="$s" '{print smp "\t" $1 "\t" $2 "\t" $3 "\t" $4 "\t" $5}' >> results/collapsed.tsv
        fi
    done
fi

exit 0