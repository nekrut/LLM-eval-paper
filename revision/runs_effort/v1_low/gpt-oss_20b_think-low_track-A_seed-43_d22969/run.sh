#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)

# Create results directory if needed
mkdir -p results

# Reference indexing (once)
REF=data/ref/chrM.fa
if [ ! -f "${REF}.amb" ]; then
    bwa index "$REF"
fi
if [ ! -f "${REF}.fai" ]; then
    samtools faidx "$REF"
fi

# Per-sample processing
for sample in "${SAMPLES[@]}"; do
    BAM=results/"$sample".bam
    BAI=results/"$sample".bam.bai
    VCF_GZ=results/"$sample".vcf.gz
    VCF_TBI=results/"$sample".vcf.gz.tbi

    # Skip if final VCF index exists (idempotent)
    if [ -f "$VCF_TBI" ]; then
        continue
    fi

    # Alignment and sorting to BAM
    if [ ! -f "$BAM" ] || [ "$(find data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz -newer "$BAM")" ]; then
        bwa mem -t "$THREADS" \
            -R "@RG\\tID:${sample}\\tSM:${sample}\\tLB:${sample}\\tPL:ILLUMINA" \
            "$REF" \
            data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz | \
        samtools sort -@ "$THREADS" -o "$BAM"
    fi

    # BAM indexing
    if [ ! -f "$BAI" ] || [ "$(find "$BAM" -newer "$BAI")" ]; then
        samtools index -@ "$THREADS" "$BAM"
    fi

    # Variant calling with lofreq
    VCF=results/"$sample".vcf
    if [ ! -f "$VCF_GZ" ] || [ "$(find "$BAM" -newer "$VCF_GZ")" ]; then
        lofreq call-parallel --pp-threads "$THREADS" \
            -f "$REF" -b "$BAM" -o "$VCF"
    fi

    # Compress and index VCF
    if [ ! -f "$VCF_GZ" ] || [ "$(find "$VCF" -newer "$VCF_GZ")" ]; then
        bgzip -c "$VCF" > "$VCF_GZ"
        tabix -p vcf "$VCF_GZ"
        rm -f "$VCF"
    fi
done

# Collapse step
COLLAPSED=results/collapsed.tsv
REGEN=true
if [ -f "$COLLAPSED" ]; then
    for sample in "${SAMPLES[@]}"; do
        if [ "$(find results/"$sample".vcf.gz -newer "$COLLAPSED")" ]; then
            REGEN=false
            break
        fi
    done
fi

if $REGEN; then
    {
        echo -e "sample\tchrom\tpos\tref\talt\taf"
        for sample in "${SAMPLES[@]}"; do
            bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" results/"$sample".vcf.gz
        done
    } > "$COLLAPSED"
fi

exit 0