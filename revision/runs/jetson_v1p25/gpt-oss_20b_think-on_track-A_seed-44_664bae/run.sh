#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES="M117-bl M117-ch M117C1-bl M117C1-ch"

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
for sample in $SAMPLES; do
    READ1=data/raw/${sample}_1.fq.gz
    READ2=data/raw/${sample}_2.fq.gz
    BAM=results/${sample}.bam
    BAI=results/${sample}.bam.bai
    VCF=results/${sample}.vcf
    GZ=${VCF}.gz

    # Alignment: skip if BAM newer than reads
    if [ ! -f "$BAM" ] || \
       [ "$READ1" -nt "$BAM" ] || \
       [ "$READ2" -nt "$BAM" ]; then
        bwa mem -t $THREADS -R "@RG\\tID:${sample}\\tSM:${sample}\\tLB:${sample}\\tPL:ILLUMINA" \
            "$REF" "$READ1" "$READ2" | samtools sort -@ $THREADS -o "$BAM"
    fi

    # BAM indexing
    if [ ! -f "$BAI" ] || [ "$BAM" -nt "$BAI" ]; then
        samtools index -@ $THREADS "$BAM"
    fi

    # Variant calling with lofreq
    if [ ! -f "$VCF" ] || [ "$BAM" -nt "$VCF" ]; then
        lofreq call-parallel --pp-threads 4 -f "$REF" -o "$VCF" "$BAM"
    fi

    # Compress VCF with bgzip and index
    if [ ! -f "$GZ" ] || [ "$VCF" -nt "$GZ" ]; then
        bgzip -c "$VCF" > "$GZ"
        tabix -p vcf "$GZ"
        rm -f "$VCF"
    fi
done

# Collapse step: rebuild if any VCF.gz newer than collapsed.tsv
COLLAPSED=results/collapsed.tsv
rebuild=false
if [ ! -f "$COLLAPSED" ]; then
    rebuild=true
else
    for sample in $SAMPLES; do
        GZ=results/${sample}.vcf.gz
        if [ "$GZ" -nt "$COLLAPSED" ]; then
            rebuild=true
            break
        fi
    done
fi

if $rebuild; then
    tmp=$(mktemp)
    echo -e "sample\tchrom\tpos\tref\talt\taf" > "$tmp"
    for sample in $SAMPLES; do
        VZ=results/${sample}.vcf.gz
        bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "$VZ" >> "$tmp"
    done
    mv "$tmp" "$COLLAPSED"
fi

exit 0