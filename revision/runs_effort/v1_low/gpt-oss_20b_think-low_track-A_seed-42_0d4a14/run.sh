#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)

# Create results directory if needed
mkdir -p results

#####################
# Reference indexing
#####################
REF=data/ref/chrM.fa
if [ ! -f "${REF}.amb" ]; then
    samtools faidx "$REF"
    bwa index "$REF"
fi

#########################
# Per-sample processing
#########################
for sample in "${SAMPLES[@]}"; do
    BAM=results/${sample}.bam
    BAI=results/${sample}.bam.bai
    VCF=results/${sample}.vcf
    VCFZ=results/${sample}.vcf.gz
    TBIX=results/${sample}.vcf.gz.tbi

    # Skip if final vcf index exists (idempotent)
    if [ -f "$TBIX" ]; then
        continue
    fi

    # Alignment + sorting
    if [ ! -f "$BAM" ]; then
        bwa mem -t "$THREADS" \
            -R "@RG\\tID:${sample}\\tSM:${sample}\\tLB:${sample}\\tPL:ILLUMINA" \
            data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz |
            samtools sort -@ "$THREADS" -o "$BAM"
    fi

    # BAM index
    if [ ! -f "$BAI" ]; then
        samtools index -@ "$THREADS" "$BAM"
    fi

    # Variant calling with lofreq
    if [ ! -f "$VCF" ]; then
        lofreq call-parallel --pp-threads "$THREADS" \
            -f "$REF" -b "$BAM" > "$VCF"
    fi

    # Compress and index VCF
    if [ ! -f "$VCFZ" ]; then
        bgzip -c "$VCF" > "$VCFZ"
    fi
    if [ ! -f "$TBIX" ]; then
        tabix -p vcf "$VCFZ"
    fi

    # Clean up intermediate VCF
    rm -f "$VCF"
done

#########################
# Collapse table
#########################
COLLAPSED=results/collapsed.tsv
REBUILD=false
if [ ! -f "$COLLAPSED" ]; then
    REBUILD=true
else
    for sample in "${SAMPLES[@]}"; do
        if [ "$(stat -c %Y results/${sample}.vcf.gz.tbi)" -gt "$(stat -c %Y $COLLAPSED)" ]; then
            REBUILD=true
            break
        fi
    done
fi

if $REBUILD; then
    {
        echo -e "sample\tchrom\tpos\tref\talt\taf"
        for sample in "${SAMPLES[@]}"; do
            bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" results/${sample}.vcf.gz
        done
    } > "$COLLAPSED.tmp" && mv "$COLLAPSED.tmp" "$COLLAPSED"
fi

exit 0