#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

mkdir -p results

REF="data/ref/chrM.fa"
FAI="${REF}.fai"

if [ ! -s "$FAI" ]; then
    samtools faidx "$REF"
fi

BWA_INDEX_FILES=("${REF}.amb" "${REF}.ann" "${REF}.bwt" "${REF}.pac" "${REF}.sa")
need_bwa_index=false
for f in "${BWA_INDEX_FILES[@]}"; do
    if [ ! -s "$f" ]; then
        need_bwa_index=true
        break
    fi
done

if $need_bwa_index; then
    bwa index "$REF"
fi

for sample in "${SAMPLES[@]}"; do
    BAM="results/${sample}.bam"
    BAI="results/${sample}.bam.bai"
    VCF="results/${sample}.vcf"
    VCFZ="results/${sample}.vcf.gz"
    VCFZTBI="results/${sample}.vcf.gz.tbi"

    FASTQ1="data/raw/${sample}_1.fq.gz"
    FASTQ2="data/raw/${sample}_2.fq.gz"

    if [ ! -s "$BAM" ] || [ "$BAM" -ot "$FASTQ1" ] || [ "$BAM" -ot "$FASTQ2" ]; then
        bwa mem -t "$THREADS" -R '@RG\tID:'"$sample"'\tSM:'"$sample"'\tLB:'"$sample"'\tPL:ILLUMINA' \
            "$REF" "$FASTQ1" "$FASTQ2" | samtools sort -@ "$THREADS" -o "$BAM"
    fi

    if [ ! -s "$BAI" ] || [ "$BAI" -ot "$BAM" ]; then
        samtools index -@ "$THREADS" "$BAM"
    fi

    if [ ! -s "$VCF" ] || [ "$VCF" -ot "$BAM" ]; then
        lofreq call-parallel --pp-threads "$THREADS" -f "$REF" -o "$VCF" "$BAM"
    fi

    if [ ! -s "$VCFZ" ] || [ "$VCFZ" -ot "$VCF" ]; then
        bgzip -c "$VCF" > "$VCFZ"
        rm -f "$VCF"
    fi

    if [ ! -s "$VCFZTBI" ] || [ "$VCFZTBI" -ot "$VCFZ" ]; then
        tabix -p vcf "$VCFZ"
    fi
done

COLLAPSED="results/collapsed.tsv"

rebuild=false
if [ ! -s "$COLLAPSED" ]; then
    rebuild=true
else
    for sample in "${SAMPLES[@]}"; do
        VCFZ="results/${sample}.vcf.gz"
        if [ "$VCFZ" -ot "$COLLAPSED" ]; then
            rebuild=true
            break
        fi
    done
fi

if $rebuild; then
    printf "sample\tchrom\tpos\tref\talt\taf\n" > "$COLLAPSED"
    for sample in "${SAMPLES[@]}"; do
        VCFZ="results/${sample}.vcf.gz"
        FORMAT=$(printf "%s\t%%CHROM\t%%POS\t%%REF\t%%ALT\t%%INFO/AF\n" "$sample")
        bcftools query -f "$FORMAT" "$VCFZ" >> "$COLLAPSED"
    done
fi

exit 0