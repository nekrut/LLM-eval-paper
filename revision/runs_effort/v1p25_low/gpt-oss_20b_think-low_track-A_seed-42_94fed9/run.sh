#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)

# Create results directory if needed
mkdir -p results

# Reference indexing (once)
REF=data/ref/chrM.fa
if [ ! -f "${REF}.fai" ]; then
    samtools faidx "$REF"
fi
if [ ! -f "${REF}.amb" ]; then
    bwa index "$REF"
fi

# Per-sample processing
for sample in "${SAMPLES[@]}"; do
    BAM=results/"$sample".bam
    BAI=results/"$sample".bam.bai
    VCF=results/"$sample".vcf
    VCFZ=results/"$sample".vcf.gz
    TBIV=results/"$sample".vcf.gz.tbi

    # Alignment and sorting
    if [ ! -f "$BAM" ] || [ "$(find data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz -newer "$BAM")" ]; then
        bwa mem -t "$THREADS" -R "@RG\\tID:${sample}\\tSM:${sample}\\tLB:${sample}\\tPL:ILLUMINA" \
            data/raw/"${sample}"_1.fq.gz data/raw/"${sample}"_2.fq.gz |
        samtools sort -@ "$THREADS" -o "$BAM"
    fi

    # BAM indexing
    if [ ! -f "$BAI" ] || [ "$(find "$BAM" -newer "$BAI")" ]; then
        samtools index -@ "$THREADS" "$BAM"
    fi

    # Variant calling
    if [ ! -f "$VCFZ" ] || [ "$(find "$BAM" -newer "$VCFZ")" ]; then
        lofreq call-parallel --pp-threads "$THREADS" -f "$REF" -o "$VCF" "$BAM"
        bgzip -c "$VCF" > "$VCFZ"
        tabix -p vcf "$VCFZ"
        rm -f "$VCF"
    fi
done

# Collapse step
COLLAPSED=results/collapsed.tsv
REBUILD=false
for sample in "${SAMPLES[@]}"; do
    VCFZ=results/"$sample".vcf.gz
    if [ ! -f "$COLLAPSED" ] || [ "$(find "$VCFZ" -newer "$COLLAPSED")" ]; then
        REBUILD=true
        break
    fi
done

if $REBUILD; then
    {
        echo -e "sample\tchrom\tpos\tref\talt\taf"
        for sample in "${SAMPLES[@]}"; do
            bcftools query -f '{sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' results/"$sample".vcf.gz
        done
    } > "$COLLAPSED"
fi

exit 0