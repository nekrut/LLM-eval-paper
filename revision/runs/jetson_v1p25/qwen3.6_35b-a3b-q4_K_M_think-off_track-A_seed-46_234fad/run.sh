#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)

mkdir -p results

# Step 2: Reference indexing (idempotent)
REF=data/ref/chrM.fa
if [ ! -f "${REF}.fai" ] || [ ! -f "$(echo ${REF} | sed 's/.fa$//').amb" ]; then
    samtools faidx "$REF"
    bwa index "$REF"
fi

# Step 3-7: Per-sample processing
for sample in "${SAMPLES[@]}"; do
    BAM="results/${sample}.bam"
    BAI="results/${sample}.bam.bai"
    VCF_GZ="results/${sample}.vcf.gz"
    TBI="results/${sample}.vcf.gz.tbi"

    # Step 3-4: Alignment and sorting (idempotent)
    if [ ! -f "$BAM" ] || [ "$(stat -c %Y "$BAM")" -lt "$(stat -c %Y data/raw/${sample}_1.fq.gz)" ]; then
        bwa mem -t $THREADS \
            -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
            "$REF" \
            "data/raw/${sample}_1.fq.gz" \
            "data/raw/${sample}_2.fq.gz" | \
        samtools sort -@ $THREADS -o "$BAM" -
    fi

    # Step 5: BAM indexing (idempotent)
    if [ ! -f "$BAI" ]; then
        samtools index -@ $THREADS "$BAM"
    fi

    # Step 6-7: Variant calling, compression, indexing (idempotent)
    VCF="results/${sample}.vcf"
    if [ ! -f "$TBI" ] || [ "$(stat -c %Y "$VCF_GZ")" -lt "$(stat -c %Y "$BAM")" ]; then
        lofreq call-parallel --pp-threads 4 -f "$REF" -o "$VCF" "$BAM"
        bgzip -f "$VCF"
        tabix -p vcf "$VCF_GZ"
    fi
done

# Step 8: Collapse step (idempotent)
COLLAPSED="results/collapsed.tsv"
REBUILD=false
for sample in "${SAMPLES[@]}"; do
    VCF_GZ="results/${sample}.vcf.gz"
    if [ ! -f "$COLLAPSED" ] || [ "$(stat -c %Y "$VCF_GZ")" -gt "$(stat -c %Y "$COLLAPSED")" ]; then
        REBUILD=true
        break
    fi
done

if [ "$REBUILD" = true ]; then
    {
        printf "sample\tchrom\tpos\tref\talt\taf\n"
        for sample in "${SAMPLES[@]}"; do
            bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "results/${sample}.vcf.gz"
        done
    } > "$COLLAPSED"
fi