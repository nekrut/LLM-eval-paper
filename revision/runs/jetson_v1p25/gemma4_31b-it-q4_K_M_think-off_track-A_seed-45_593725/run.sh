#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
REF="data/ref/chrM.fa"
OUTDIR="results"

mkdir -p "$OUTDIR"

# 2. Reference indexing
if [[ ! -f "${REF}.fai" ]]; then
    samtools faidx "$REF"
fi

if [[ ! -f "${REF}.bwt" ]]; then
    bwa index "$REF"
fi

# Per-sample processing
for sample in "${SAMPLES[@]}"; do
    R1="data/raw/${sample}_1.fq.gz"
    R2="data/raw/${sample}_2.fq.gz"
    BAM="${OUTDIR}/${sample}.bam"
    BAI="${BAM}.bai"
    VCF_GZ="${OUTDIR}/${sample}.vcf.gz"
    VCF_TBI="${VCF_GZ}.tbi"

    # 3 & 4. Alignment and Sort
    if [[ ! -f "$BAM" ]] || [[ "$R1" -nt "$BAM" ]] || [[ "$R2" -nt "$BAM" ]]; then
        bwa mem -t "$THREADS" -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" "$REF" "$R1" "$R2" | \
        samtools sort -@ "$THREADS" -o "$BAM"
    fi

    # 5. BAM Indexing
    if [[ ! -f "$BAI" ]] || [[ "$BAM" -nt "$BAI" ]]; then
        samtools index -@ "$THREADS" "$BAM"
    fi

    # 6 & 7. Variant Calling and Compression
    if [[ ! -f "$VCF_TBI" ]] || [[ "$BAM" -nt "$VCF_TBI" ]]; then
        lofreq call-parallel --pp-threads "$THREADS" -f "$REF" -o "${OUTDIR}/${sample}.vcf" "$BAM"
        bgzip -f "${OUTDIR}/${sample}.vcf"
        tabix -p vcf "$VCF_GZ"
    fi
done

# 8. Collapse step
COLLAPSED="${OUTDIR}/collapsed.tsv"
NEEDS_REBUILD=false

if [[ ! -f "$COLLAPSED" ]]; then
    NEEDS_REBUILD=true
else
    for sample in "${SAMPLES[@]}"; do
        VCF_GZ="${OUTDIR}/${sample}.vcf.gz"
        if [[ "$VCF_GZ" -nt "$COLLAPSED" ]]; then
            NEEDS_REBUILD=true
            break
        fi
    done
fi

if [ "$NEEDS_REBUILD" = true ]; then
    printf "sample\tchrom\tpos\tref\talt\taf\n" > "$COLLAPSED"
    for sample in "${SAMPLES[@]}"; do
        bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "${OUTDIR}/${sample}.vcf.gz" >> "$COLLAPSED"
    done
fi